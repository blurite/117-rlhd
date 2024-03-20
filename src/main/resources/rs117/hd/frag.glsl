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

#include uniforms/materials.glsl
#include uniforms/water_types.glsl
#include uniforms/lights.glsl

#include MATERIAL_CONSTANTS

uniform sampler2DArray textureArray;
uniform sampler2D shadowMap;

uniform vec3 cameraPos;
uniform mat4 lightProjectionMatrix;
uniform float elapsedTime;
uniform float colorBlindnessIntensity;
uniform vec3 fogColor;
uniform float fogDepth;
uniform vec3 waterColorLight;
uniform vec3 waterColorMid;
uniform vec3 waterColorDark;
uniform vec3 ambientColor;
uniform float ambientStrength;
uniform vec3 lightColor;
uniform float lightStrength;
uniform vec3 underglowColor;
uniform float underglowStrength;
uniform float groundFogStart;
uniform float groundFogEnd;
uniform float groundFogOpacity;
uniform float lightningBrightness;
uniform vec3 lightDir;
uniform float shadowMaxBias;
uniform int shadowsEnabled;
uniform int filterTypePrevious;
uniform int filterType;
uniform int fadeProgress;
uniform float startTimeMillis;
uniform float endTimeMillis;
uniform float currentTimeMillis;
uniform bool underwaterEnvironment;
uniform bool underwaterCaustics;
uniform vec3 underwaterCausticsColor;
uniform float underwaterCausticsStrength;

// general HD settings
uniform float saturation;
uniform float contrast;

uniform int pointLightsCount; // number of lights in current frame

flat in vec4 vColor[3];
flat in vec3 vUv[3];
flat in int vMaterialData[3];
flat in int vTerrainData[3];
flat in vec3 T;
flat in vec3 B;

in FragmentData {
    vec3 position;
    vec3 normal;
    vec3 texBlend;
    float fogAmount;
} IN;

out vec4 FragColor;

vec2 worldUvs(float scale) {
    return -IN.position.xz / (128 * scale);
}

#include utils/constants.glsl
#include utils/misc.glsl
#include utils/color_blindness.glsl
#include utils/caustics.glsl
#include utils/color_utils.glsl
#include utils/normals.glsl
#include utils/specular.glsl
#include utils/displacement.glsl
#include utils/shadows.glsl
#include utils/water.glsl

vec3 getFilter(int index, vec3 color) {
    if (index == 1) {
        return vec3(dot(color, vec3(0.2126, 0.7152, 0.0722)));
    } else if (index == 2) {
        return vec3(
            dot(color, vec3(0.393, 0.769, 0.189)),
            dot(color, vec3(0.349, 0.686, 0.168)),
            dot(color, vec3(0.272, 0.534, 0.131))
        );
    } else if (index == 3) {
        float intensity = dot(color, vec3(0.2126, 0.7152, 0.0722));
        float modifier = 2.2;
        return vec3(
            intensity + (color.r - intensity) * modifier,
            intensity + (color.g - intensity) * modifier,
            intensity + (color.b - intensity) * modifier
        );
    } else if(index == 4) {
       float threshold = 0.5;
       float smoothness = 0.2;
       vec3 shadedColor = smoothstep(threshold - smoothness, threshold + smoothness, color);
       return mix(color, shadedColor, 0.6);
    } else if(index == 5) {

        float quantizationLevels = 7.0;
        vec3 quantizedColor = floor(color * quantizationLevels) / quantizationLevels;
        return quantizedColor;
    }
    return color;
}

vec3 applyFilter(vec3 color) {
    vec3 filteredColor = color;

    vec3 previousFilteredColor = getFilter(filterTypePrevious, color);
    vec3 newFilteredColor = getFilter(filterType, color);

    // Convert fadeProgress from 3 ticks to milliseconds
    float fadeMilliseconds = fadeProgress * 600.0; // 600 ms/tick

    // Convert fadeMilliseconds to 0-1 range
    float fadeAmount = clamp(fadeMilliseconds / 1800.0, 0.0, 1.0); // 3 seconds * 600 ms/tick

    // Smooth out the fadeAmount using cubic interpolation
    float smoothedFade = smoothstep(0.0, 1.0, fadeAmount);
    smoothedFade = smoothstep(0.0, 1.0, smoothedFade);

    // Interpolate between old and new filter types based on fade progress
    filteredColor = mix(previousFilteredColor, newFilteredColor, 1.0 - smoothedFade); // Invert smoothedFade for correct fading

    return filteredColor;
}



void main() {
    vec3 downDir = vec3(0, -1, 0);
    // View & light directions are from the fragment to the camera/light
    vec3 viewDir = normalize(cameraPos - IN.position);

    Material material1 = getMaterial(vMaterialData[0] >> MATERIAL_INDEX_SHIFT);
    Material material2 = getMaterial(vMaterialData[1] >> MATERIAL_INDEX_SHIFT);
    Material material3 = getMaterial(vMaterialData[2] >> MATERIAL_INDEX_SHIFT);

    // Water data
    bool isTerrain = (vTerrainData[0] & 1) != 0; // 1 = 0b1
    int waterDepth1 = vTerrainData[0] >> 8 & 0x7FF;
    int waterDepth2 = vTerrainData[1] >> 8 & 0x7FF;
    int waterDepth3 = vTerrainData[2] >> 8 & 0x7FF;
    float waterDepth =
        waterDepth1 * IN.texBlend.x +
        waterDepth2 * IN.texBlend.y +
        waterDepth3 * IN.texBlend.z;
    int waterTypeIndex = isTerrain ? vTerrainData[0] >> 3 & 0x1F : 0;
    WaterType waterType = getWaterType(waterTypeIndex);

    // set initial texture map ids
    int colorMap1 = material1.colorMap;
    int colorMap2 = material2.colorMap;
    int colorMap3 = material3.colorMap;

    // only use one flowMap map
    int flowMap = material1.flowMap;

    bool isUnderwater = waterDepth != 0;
    bool isWater = waterTypeIndex > 0 && !isUnderwater;

    vec4 outputColor = vec4(1);

    if (isWater) {
        outputColor = sampleWater(waterTypeIndex, viewDir);
    } else {
        vec2 uv1 = vUv[0].xy;
        vec2 uv2 = vUv[1].xy;
        vec2 uv3 = vUv[2].xy;
        vec2 blendedUv = uv1 * IN.texBlend.x + uv2 * IN.texBlend.y + uv3 * IN.texBlend.z;

        float mipBias = 0;
        // Vanilla tree textures rely on UVs being clamped horizontally,
        // which HD doesn't do, so we instead opt to hide these fragments
        if ((vMaterialData[0] >> MATERIAL_FLAG_VANILLA_UVS & 1) == 1) {
            blendedUv.x = clamp(blendedUv.x, 0, .984375);

            // Make fishing spots easier to see
            if (colorMap1 == MAT_WATER_DROPLETS.colorMap)
                mipBias = -100;
        }

        uv1 = uv2 = uv3 = blendedUv;

        // Scroll UVs
        uv1 += material1.scrollDuration * elapsedTime;
        uv2 += material2.scrollDuration * elapsedTime;
        uv3 += material3.scrollDuration * elapsedTime;

        // Scale from the center
        uv1 = (uv1 - .5) * material1.textureScale + .5;
        uv2 = (uv2 - .5) * material2.textureScale + .5;
        uv3 = (uv3 - .5) * material3.textureScale + .5;

        // get flowMap map
        vec2 flowMapUv = uv1 - animationFrame(material1.flowMapDuration);
        float flowMapStrength = material1.flowMapStrength;
        if (isUnderwater)
        {
            // Distort underwater textures
            flowMapUv = worldUvs(1.5) + animationFrame(10 * waterType.duration) * vec2(1, -1);
            flowMapStrength = 0.075;
        }

        vec2 uvFlow = texture(textureArray, vec3(flowMapUv, flowMap)).xy;
        uv1 += uvFlow * flowMapStrength;
        uv2 += uvFlow * flowMapStrength;
        uv3 += uvFlow * flowMapStrength;

        // Set up tangent-space transformation matrix
        vec3 N = normalize(IN.normal);
        mat3 TBN = mat3(T, B, N * min(length(T), length(B)));

        float selfShadowing = 0;
        vec3 fragPos = IN.position;
        #if PARALLAX_OCCLUSION_MAPPING
        mat3 invTBN = inverse(TBN);
        vec3 tsViewDir = invTBN * viewDir;
        vec3 tsLightDir = invTBN * -lightDir;

        vec3 fragDelta = vec3(0);

        sampleDisplacementMap(material1, tsViewDir, tsLightDir, uv1, fragDelta, selfShadowing);
        sampleDisplacementMap(material2, tsViewDir, tsLightDir, uv2, fragDelta, selfShadowing);
        sampleDisplacementMap(material3, tsViewDir, tsLightDir, uv3, fragDelta, selfShadowing);

        // Average
        fragDelta /= 3;
        selfShadowing /= 3;

        fragPos += TBN * fragDelta;
        #endif

        // get vertex colors
        vec4 flatColor = vec4(0.5, 0.5, 0.5, 1.0);
        vec4 baseColor1 = vColor[0];
        vec4 baseColor2 = vColor[1];
        vec4 baseColor3 = vColor[2];

        #if VANILLA_COLOR_BANDING
        vec4 baseColor =
            IN.texBlend[0] * baseColor1 +
            IN.texBlend[1] * baseColor2 +
            IN.texBlend[2] * baseColor3;

        baseColor.rgb = linearToSrgb(baseColor.rgb);
        baseColor.rgb = srgbToHsv(baseColor.rgb);
        baseColor.b = floor(baseColor.b * 127) / 127;
        baseColor.rgb = hsvToSrgb(baseColor.rgb);
        baseColor.rgb = srgbToLinear(baseColor.rgb);

        baseColor1 = baseColor2 = baseColor3 = baseColor;
        #endif

        // get diffuse textures
        vec4 texColor1 = colorMap1 == -1 ? vec4(1) : texture(textureArray, vec3(uv1, colorMap1), mipBias);
        vec4 texColor2 = colorMap2 == -1 ? vec4(1) : texture(textureArray, vec3(uv2, colorMap2), mipBias);
        vec4 texColor3 = colorMap3 == -1 ? vec4(1) : texture(textureArray, vec3(uv3, colorMap3), mipBias);
        texColor1.rgb *= material1.brightness;
        texColor2.rgb *= material2.brightness;
        texColor3.rgb *= material3.brightness;

        ivec3 isOverlay = ivec3(
            vMaterialData[0] >> MATERIAL_FLAG_IS_OVERLAY & 1,
            vMaterialData[1] >> MATERIAL_FLAG_IS_OVERLAY & 1,
            vMaterialData[2] >> MATERIAL_FLAG_IS_OVERLAY & 1
        );
        int overlayCount = isOverlay[0] + isOverlay[1] + isOverlay[2];
        ivec3 isUnderlay = ivec3(1) - isOverlay;
        int underlayCount = isUnderlay[0] + isUnderlay[1] + isUnderlay[2];

        // calculate blend amounts for overlay and underlay vertices
        vec3 underlayBlend = IN.texBlend * isUnderlay;
        vec3 overlayBlend = IN.texBlend * isOverlay;

        if (underlayCount == 0 || overlayCount == 0)
        {
            // if a tile has all overlay or underlay vertices,
            // use the default blend

            underlayBlend = IN.texBlend;
            overlayBlend = IN.texBlend;
        }
        else
        {
            // if there's a mix of overlay and underlay vertices,
            // calculate custom blends for each 'layer'

            float underlayBlendMultiplier = 1.0 / (underlayBlend[0] + underlayBlend[1] + underlayBlend[2]);
            // adjust back to 1.0 total
            underlayBlend *= underlayBlendMultiplier;
            underlayBlend = clamp(underlayBlend, 0, 1);

            float overlayBlendMultiplier = 1.0 / (overlayBlend[0] + overlayBlend[1] + overlayBlend[2]);
            // adjust back to 1.0 total
            overlayBlend *= overlayBlendMultiplier;
            overlayBlend = clamp(overlayBlend, 0, 1);
        }


        // get fragment colors by combining vertex colors and texture samples
        vec4 texA = getMaterialShouldOverrideBaseColor(material1) ? texColor1 : vec4(texColor1.rgb * baseColor1.rgb, min(texColor1.a, baseColor1.a));
        vec4 texB = getMaterialShouldOverrideBaseColor(material2) ? texColor2 : vec4(texColor2.rgb * baseColor2.rgb, min(texColor2.a, baseColor2.a));
        vec4 texC = getMaterialShouldOverrideBaseColor(material3) ? texColor3 : vec4(texColor3.rgb * baseColor3.rgb, min(texColor3.a, baseColor3.a));

        // combine fragment colors based on each blend, creating
        // one color for each overlay/underlay 'layer'
        vec4 underlayColor = texA * underlayBlend.x + texB * underlayBlend.y + texC * underlayBlend.z;
        vec4 overlayColor = texA * overlayBlend.x + texB * overlayBlend.y + texC * overlayBlend.z;

        float overlayMix = 0;

        if (overlayCount > 0 && underlayCount > 0)
        {
            // custom blending logic for blending overlays into underlays
            // in a style similar to 2008+ HD

            // fragment UV
            vec2 fragUv = blendedUv;
            // standalone UV
            // e.g. if there are 2 overlays and 1 underlay, the underlay is the standalone
            vec2 sUv[3];
            bool inverted = false;

            ivec3 isPrimary = isUnderlay;
            if (overlayCount == 1) {
                isPrimary = isOverlay;
                // we use this at the end of this logic to invert
                // the result if there's 1 overlay, 2 underlay
                // vs the default result from 1 underlay, 2 overlay
                inverted = true;
            }

            if (isPrimary[0] == 1) {
                sUv = vec2[](vUv[0].xy, vUv[1].xy, vUv[2].xy);
            } else if (isPrimary[1] == 1) {
                sUv = vec2[](vUv[1].xy, vUv[0].xy, vUv[2].xy);
            } else {
                sUv = vec2[](vUv[2].xy, vUv[0].xy, vUv[1].xy);
            }

            // point on side perpendicular to sUv[0]
            vec2 oppositePoint = sUv[1] + pointToLine(sUv[1], sUv[2], sUv[0]) * (sUv[2] - sUv[1]);

            // calculate position of fragment's UV relative to
            // line between sUv[0] and oppositePoint
            float result = pointToLine(sUv[0], oppositePoint, fragUv);

            if (inverted)
            {
                result = 1 - result;
            }

            result = clamp(result, 0, 1);

            float distance = distance(sUv[0], oppositePoint);

            float cutoff = 0.5;

            result = (result - (1.0 - cutoff)) * (1.0 / cutoff);
            result = clamp(result, 0, 1);

            float maxDistance = 2.5;
            if (distance > maxDistance)
            {
                float multi = distance / maxDistance;
                result = 1.0 - ((1.0 - result) * multi);
                result = clamp(result, 0, 1);
            }

            overlayMix = result;
        }

        outputColor = mix(underlayColor, overlayColor, overlayMix);

        // normals
        vec3 normals;
        if ((vMaterialData[0] >> MATERIAL_FLAG_UPWARDS_NORMALS & 1) == 1) {
            normals = vec3(0, -1, 0);
        } else {
            vec3 n1 = sampleNormalMap(material1, uv1, TBN);
            vec3 n2 = sampleNormalMap(material2, uv2, TBN);
            vec3 n3 = sampleNormalMap(material3, uv3, TBN);
            normals = normalize(n1 * IN.texBlend.x + n2 * IN.texBlend.y + n3 * IN.texBlend.z);
        }

        float lightDotNormals = dot(normals, lightDir);
        float downDotNormals = dot(downDir, normals);
        float viewDotNormals = dot(viewDir, normals);

        #if (DISABLE_DIRECTIONAL_SHADING)
        lightDotNormals = .7;
        #endif

        float shadow = 0;
        if ((vMaterialData[0] >> MATERIAL_FLAG_DISABLE_SHADOW_RECEIVING & 1) == 0)
            shadow = sampleShadowMap(fragPos, waterTypeIndex, vec2(0), lightDotNormals);
        shadow = max(shadow, selfShadowing);
        float inverseShadow = 1 - shadow;



        // specular
        vec3 vSpecularGloss = vec3(material1.specularGloss, material2.specularGloss, material3.specularGloss);
        vec3 vSpecularStrength = vec3(material1.specularStrength, material2.specularStrength, material3.specularStrength);
        vSpecularStrength *= vec3(
            material1.roughnessMap == -1 ? 1 : linearToSrgb(texture(textureArray, vec3(uv1, material1.roughnessMap)).r),
            material2.roughnessMap == -1 ? 1 : linearToSrgb(texture(textureArray, vec3(uv2, material2.roughnessMap)).r),
            material3.roughnessMap == -1 ? 1 : linearToSrgb(texture(textureArray, vec3(uv3, material3.roughnessMap)).r)
        );

        // apply specular highlights to anything semi-transparent
        // this isn't always desirable but adds subtle light reflections to windows, etc.
        if (baseColor1.a + baseColor2.a + baseColor3.a < 2.99)
        {
            vSpecularGloss = vec3(30);
            vSpecularStrength = vec3(
                clamp((1 - baseColor1.a) * 2, 0, 1),
                clamp((1 - baseColor2.a) * 2, 0, 1),
                clamp((1 - baseColor3.a) * 2, 0, 1)
            );
        }
        float combinedSpecularStrength = dot(vSpecularStrength, IN.texBlend);


        // calculate lighting

        // ambient light
        vec3 ambientLightOut = ambientColor * ambientStrength;

        float aoFactor =
            IN.texBlend.x * (material1.ambientOcclusionMap == -1 ? 1 : texture(textureArray, vec3(uv1, material1.ambientOcclusionMap)).r) +
            IN.texBlend.y * (material2.ambientOcclusionMap == -1 ? 1 : texture(textureArray, vec3(uv2, material2.ambientOcclusionMap)).r) +
            IN.texBlend.z * (material3.ambientOcclusionMap == -1 ? 1 : texture(textureArray, vec3(uv3, material3.ambientOcclusionMap)).r);
        ambientLightOut *= aoFactor;

        // directional light
        vec3 dirLightColor = lightColor * lightStrength;

        // underwater caustics based on directional light
        if (underwaterCaustics && underwaterEnvironment) {
            float scale = 12.8;
            vec2 causticsUv = worldUvs(scale);

            const ivec2 direction = ivec2(1, -1);
            const int driftSpeed = 231;
            vec2 drift = animationFrame(231) * ivec2(1, -2);
            vec2 flow1 = causticsUv + animationFrame(19) * direction + drift;
            vec2 flow2 = causticsUv * 1.25 + animationFrame(37) * -direction + drift;

            vec3 caustics = sampleCaustics(flow1, flow2) * 2;

            vec3 causticsColor = underwaterCausticsColor * underwaterCausticsStrength;
            dirLightColor += caustics * causticsColor * lightDotNormals * pow(lightStrength, 1.5);
        }

        // apply shadows
        dirLightColor *= inverseShadow;

        vec3 lightColor = dirLightColor;
        vec3 lightOut = max(lightDotNormals, 0.0) * lightColor;

        // directional light specular
        vec3 lightReflectDir = reflect(-lightDir, normals);
        vec3 lightSpecularOut = lightColor * specular(viewDir, lightReflectDir, vSpecularGloss, vSpecularStrength);

        // point lights
        vec3 pointLightsOut = vec3(0);
        vec3 pointLightsSpecularOut = vec3(0);
        for (int i = 0; i < pointLightsCount; i++) {
            vec4 pos = PointLightArray[i].position;
            vec3 lightToFrag = pos.xyz - IN.position;
            float distanceSquared = dot(lightToFrag, lightToFrag);
            float radiusSquared = pos.w;
            if (distanceSquared <= radiusSquared) {
                float attenuation = max(0, 1 - sqrt(distanceSquared / radiusSquared));
                attenuation *= attenuation;

                vec3 pointLightColor = PointLightArray[i].color * attenuation;
                vec3 pointLightDir = normalize(lightToFrag);

                float pointLightDotNormals = max(dot(normals, pointLightDir), 0);
                pointLightsOut += pointLightColor * pointLightDotNormals;

                vec3 pointLightReflectDir = reflect(-pointLightDir, normals);
                pointLightsSpecularOut += pointLightColor * specular(viewDir, pointLightReflectDir, vSpecularGloss, vSpecularStrength);
            }
        }

        // sky light
        vec3 skyLightColor = fogColor;
        float skyLightStrength = 0.5;
        float skyDotNormals = downDotNormals;
        vec3 skyLightOut = max(skyDotNormals, 0.0) * skyLightColor * skyLightStrength;


        // lightning
        vec3 lightningColor = vec3(.25, .25, .25);
        float lightningStrength = lightningBrightness;
        float lightningDotNormals = downDotNormals;
        vec3 lightningOut = max(lightningDotNormals, 0.0) * lightningColor * lightningStrength;


        // underglow
        vec3 underglowOut = underglowColor * max(normals.y, 0) * underglowStrength;


        // fresnel reflection
        float baseOpacity = 0.4;
        float fresnel = 1.0 - clamp(viewDotNormals, 0.0, 1.0);
        float finalFresnel = clamp(mix(baseOpacity, 1.0, fresnel * 1.2), 0.0, 1.0);
        vec3 surfaceColor = vec3(0);
        vec3 surfaceColorOut = surfaceColor * max(combinedSpecularStrength, 0.2);


        // apply lighting
        vec3 compositeLight = ambientLightOut + lightOut + lightSpecularOut + skyLightOut + lightningOut +
        underglowOut + pointLightsOut + pointLightsSpecularOut + surfaceColorOut;

        float unlit = dot(IN.texBlend, vec3(
            getMaterialIsUnlit(material1),
            getMaterialIsUnlit(material2),
            getMaterialIsUnlit(material3)
        ));
        outputColor.rgb *= mix(compositeLight, vec3(1), unlit);
        outputColor.rgb = linearToSrgb(outputColor.rgb);

        if (isUnderwater) {
            sampleUnderwater(outputColor.rgb, waterType, waterDepth, lightDotNormals);
        }
    }


    outputColor.rgb = clamp(outputColor.rgb, 0, 1);

    // Skip unnecessary color conversion if possible
    if (saturation != 1 || contrast != 1) {
        vec3 hsv = srgbToHsv(outputColor.rgb);

        // Apply saturation setting
        hsv.y *= saturation;

        // Apply contrast setting
        if (hsv.z > 0.5) {
            hsv.z = 0.5 + ((hsv.z - 0.5) * contrast);
        } else {
            hsv.z = 0.5 - ((0.5 - hsv.z) * contrast);
        }

        outputColor.rgb = hsvToSrgb(hsv);
    }

    outputColor.rgb = colorBlindnessCompensation(outputColor.rgb);
    outputColor.rgb = applyFilter(outputColor.rgb);
    // apply fog
    if (!isUnderwater) {
        // ground fog
        float distance = distance(IN.position, cameraPos);
        float closeFadeDistance = 1500;
        float groundFog = 1.0 - clamp((IN.position.y - groundFogStart) / (groundFogEnd - groundFogStart), 0.0, 1.0);
        groundFog = mix(0.0, groundFogOpacity, groundFog);
        groundFog *= clamp(distance / closeFadeDistance, 0.0, 1.0);

        // multiply the visibility of each fog
        float combinedFog = 1 - (1 - IN.fogAmount) * (1 - groundFog);

        if (isWater) {
            outputColor.a = combinedFog + outputColor.a * (1 - combinedFog);
        }

        outputColor.rgb = mix(outputColor.rgb, fogColor, combinedFog);

    }

    FragColor = outputColor;
}


