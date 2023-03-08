/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * Copyright (c) 2021, 117 <https://twitter.com/117scape>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#version 330

#define TILE_SIZE 128

#define FOG_SCENE_EDGE_MIN TILE_SIZE
#define FOG_SCENE_EDGE_MAX (103 * TILE_SIZE)
#define FOG_CORNER_ROUNDING 1.5
#define FOG_CORNER_ROUNDING_SQUARED FOG_CORNER_ROUNDING * FOG_CORNER_ROUNDING

layout (location = 0) in ivec4 VertexPosition;
layout (location = 1) in vec4 uv;
layout (location = 2) in vec4 normal;

#include uniforms/camera.glsl

uniform bool useVertexFog;
uniform float fogDepth;
uniform int drawDistance;
uniform ivec4 sceneBounds;
uniform bool extendHorizon;
uniform int horizonWaterHeight;
uniform int horizonWaterDepth;

out VertexData {
    ivec3 pos;
    vec4 normal;
    vec4 color;
    vec4 uv;
    float fogAmount;
} OUT;

#include utils/color_conversion.glsl

float fogFactorLinear(const float dist, const float start, const float end) {
    return 1.0 - clamp((dist - start) / (end - start), 0.0, 1.0);
}

void main() {
    ivec3 vertex = VertexPosition.xyz;
    int ahsl = VertexPosition.w;
    vec3 rgb = jagexHslToRgb(ahsl & 0xffff);
    float alpha = 1 - float(ahsl >> 24 & 0xff) / 255.f;

    vec4 normal = normal;
    int terrainData = int(normal.w);
    bool isTerrain = (terrainData & 1) != 0; // 1 = 0b1
    if (isTerrain) {
        int waterTypeIndex = terrainData >> 3 & 0x1F;
        bool isWater = waterTypeIndex > 0; // water surface or underwater tile
        if (isWater && (
            vertex.x == sceneBounds.x || vertex.x == sceneBounds.z ||
            vertex.z == sceneBounds.y || vertex.z == sceneBounds.w
        )) {
            int waterDepth = terrainData >> 8;
            bool isUnderwater = waterDepth != 0;
            if (isUnderwater) {
                terrainData = terrainData & ((1 << 8) - 1);
                terrainData |= horizonWaterDepth << 8;
            } else {
                vertex.y = horizonWaterHeight;
            }
        }
    }

    OUT.pos = vertex;
    OUT.normal = normal;
    OUT.color = vec4(srgbToLinear(rgb), alpha);
    OUT.uv = uv;
    OUT.fogAmount = 0;

    if (useVertexFog) {
        int fogWest = max(sceneBounds.x, cameraX - drawDistance);
        int fogEast = min(sceneBounds.z, cameraX + drawDistance - TILE_SIZE);
        int fogSouth = max(sceneBounds.y, cameraZ - drawDistance);
        int fogNorth = min(sceneBounds.w, cameraZ + drawDistance - TILE_SIZE);

        // Calculate distance from the scene edge
        int xDist = min(vertex.x - fogWest, fogEast - vertex.x);
        int zDist = min(vertex.z - fogSouth, fogNorth - vertex.z);
        float nearestEdgeDistance = min(xDist, zDist);
        float secondNearestEdgeDistance = max(xDist, zDist);
        float fogDistance = nearestEdgeDistance - FOG_CORNER_ROUNDING * TILE_SIZE *
        max(0, (nearestEdgeDistance + FOG_CORNER_ROUNDING_SQUARED) /
        (secondNearestEdgeDistance + FOG_CORNER_ROUNDING_SQUARED));

        float edgeFogDepth = 50;
        float edgeFogAmount = fogFactorLinear(fogDistance, 0, edgeFogDepth * (TILE_SIZE / 10));


        // Use a combination of two different methods of calculating distance fog.
        // The is super arbitrary and is only eyeballed to provide a similar overall
        // appearance between equal fog depths at different draw distances.

        float fogStart1 = drawDistance * 0.85;
        float distance1 = length(vec3(cameraX, cameraY, cameraZ) - vec3(vertex.x, cameraY, vertex.z));
        float distanceFogAmount1 = (distance1 - fogStart1) / (drawDistance - fogStart1);
        distanceFogAmount1 = clamp(distanceFogAmount1, 0.0, 1.0);

        float minFogStart = 0.0;
        float maxFogStart = 0.3;
        int fogDepth2 = int(fogDepth * 10 * drawDistance / TILE_SIZE);
        float fogDepthMultiplier = clamp(fogDepth2, 0, 1000) / 1000.0;
        float fogStart2 = (maxFogStart - (fogDepthMultiplier * (maxFogStart - minFogStart))) * float(drawDistance);
        float exponent = 2.71828;
        float camToVertex = length(vec3(cameraX, cameraY, cameraZ) - vec3(vertex.x, mix(float(vertex.y), float(cameraY), 0.5), vertex.z));
        float distance2 = max(camToVertex - fogStart2, 0) / max(drawDistance - fogStart2, 1);
        float density = fogDepth2 / 100.0;
        float distanceFogAmount2 = 1 / (pow(exponent, distance2 * density));
        distanceFogAmount2 = 1.0 - clamp(distanceFogAmount2, 0.0, 1.0);

        // Combine distance fogs
        float distanceFogAmount = max(distanceFogAmount1, distanceFogAmount2);

        // Combine distance fog with edge fog
        OUT.fogAmount = max(distanceFogAmount, edgeFogAmount);
    }
}
