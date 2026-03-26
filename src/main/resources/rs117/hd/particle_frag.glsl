/*
 * Particle fragment shader
 * Supports tiered texture arrays for optimal memory usage:
 * - Tier 0: 64x64 textures
 * - Tier 1: 128x128 textures
 * - Tier 2: 256x256 textures
 * - Tier 3: 1024x1024 textures
 */
#version 330 core

// One sampler per tier
uniform sampler2DArray particleTex64;
uniform sampler2DArray particleTex128;
uniform sampler2DArray particleTex256;
uniform sampler2DArray particleTex1024;

in vec4 vColor;
flat in int vTextureId;
in vec2 vUv;

out vec4 fragColor;

void main() {
    vec4 color = vColor;

    if (vTextureId > 0) {
        // Decode tier and index from texture ID
        // Subtract 1 because renderer adds 1 to distinguish from "no texture" (0)
        int encodedId = vTextureId - 1;
        int tier = (encodedId >> 14) & 0x3;
        int texIdx = encodedId & 0x3FFF;

        vec4 texColor;
        if (tier == 0) {
            texColor = texture(particleTex64, vec3(vUv, float(texIdx)));
        } else if (tier == 1) {
            texColor = texture(particleTex128, vec3(vUv, float(texIdx)));
        } else if (tier == 2) {
            texColor = texture(particleTex256, vec3(vUv, float(texIdx)));
        } else {
            texColor = texture(particleTex1024, vec3(vUv, float(texIdx)));
        }

        if (texColor.a < 0.01) {
            discard;
        }

        color = texColor * color;
    }

    if (color.a < 0.01) {
        discard;
    }

    fragColor = color;
}
