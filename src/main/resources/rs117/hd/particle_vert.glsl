/*
 * Particle vertex shader - instanced version
 * Each instance is one particle, shader generates 6 vertices per quad using gl_VertexID
 * 6x less data upload compared to per-vertex approach
 */
#version 330 core

// Instance data (one per particle, read with divisor=1)
layout(location = 0) in vec3 iCenter;   // Particle center position
layout(location = 1) in int iAbhsl;     // Packed alpha + HSL color
layout(location = 2) in ivec4 iTex;     // x=texId, y=size (fixed-point *256), z=rotation, w=spriteMeta

uniform mat4 uProjection;
uniform mat4 uView;
uniform vec3 uCamPos;    // Camera position for spherical billboarding

out vec4 vColor;
flat out int vTextureId;
out vec2 vUv;

// Quad corner offsets for 2 triangles (6 vertices)
// Triangle 1: bottom-left, top-left, bottom-right
// Triangle 2: bottom-right, top-left, top-right
const vec2 cornerOffsets[6] = vec2[6](
    vec2(-1.0, -1.0),  // 0: bottom-left
    vec2(-1.0,  1.0),  // 1: top-left
    vec2( 1.0, -1.0),  // 2: bottom-right
    vec2( 1.0, -1.0),  // 3: bottom-right
    vec2(-1.0,  1.0),  // 4: top-left
    vec2( 1.0,  1.0)   // 5: top-right
);

const vec2 uvCoords[6] = vec2[6](
    vec2(0.0, 1.0),  // 0
    vec2(0.0, 0.0),  // 1
    vec2(1.0, 1.0),  // 2
    vec2(1.0, 1.0),  // 3
    vec2(0.0, 0.0),  // 4
    vec2(1.0, 0.0)   // 5
);

// RuneScape HSL to RGB conversion
vec3 hslToRgb(vec3 hsl) {
    float hue = hsl.x / 64.0 + 0.0078125;
    float sat = hsl.y / 8.0 + 0.0625;
    float lum = hsl.z;

    float var11 = lum / 128.0;
    float r = var11;
    float g = var11;
    float b = var11;

    float var19;
    if (var11 < 0.5) {
        var19 = var11 * (1.0 + sat);
    } else {
        var19 = var11 + sat - var11 * sat;
    }

    float var21 = 2.0 * var11 - var19;
    float var23 = hue + 0.3333333333333333;
    if (var23 > 1.0) {
        var23 -= 1.0;
    }

    float var27 = hue - 0.3333333333333333;
    if (var27 < 0.0) {
        var27 += 1.0;
    }

    if (6.0 * var23 < 1.0) {
        r = var21 + (var19 - var21) * 6.0 * var23;
    } else if (2.0 * var23 < 1.0) {
        r = var19;
    } else if (3.0 * var23 < 2.0) {
        r = var21 + (var19 - var21) * (0.6666666666666666 - var23) * 6.0;
    } else {
        r = var21;
    }

    if (6.0 * hue < 1.0) {
        g = var21 + (var19 - var21) * 6.0 * hue;
    } else if (2.0 * hue < 1.0) {
        g = var19;
    } else if (3.0 * hue < 2.0) {
        g = var21 + (var19 - var21) * (0.6666666666666666 - hue) * 6.0;
    } else {
        g = var21;
    }

    if (6.0 * var27 < 1.0) {
        b = var21 + (var19 - var21) * 6.0 * var27;
    } else if (2.0 * var27 < 1.0) {
        b = var19;
    } else if (3.0 * var27 < 2.0) {
        b = var21 + (var19 - var21) * (0.6666666666666666 - var27) * 6.0;
    } else {
        b = var21;
    }

    return vec3(r, g, b);
}

void main() {
    // Which corner of the quad (0-5)
    int cornerIdx = gl_VertexID % 6;
    vec2 corner = cornerOffsets[cornerIdx];

    // Size from iTex.y (fixed-point, divide by 256)
    float size = float(iTex.y) / 256.0;

    // Rotation from iTex.z (0-65535 -> 0-2*PI radians)
    float rotation = float(iTex.z) / 65536.0 * 6.28318530718;
    float cosR = cos(rotation);
    float sinR = sin(rotation);
    // Apply 2D rotation to corner offset
    corner = vec2(corner.x * cosR - corner.y * sinR, corner.x * sinR + corner.y * cosR);

    // Compute per-particle billboard vectors (spherical billboarding)
    vec3 toCam = uCamPos - iCenter;
    float dist = length(toCam);
    if (dist < 0.001) {
        toCam = vec3(0.0, 0.0, 1.0);
    } else {
        toCam /= dist;
    }

    // World up vector
    vec3 worldUp = vec3(0.0, 1.0, 0.0);

    // right = normalize(cross(worldUp, toCam))
    vec3 right = cross(worldUp, toCam);
    float rightLen = length(right);
    if (rightLen < 0.001) {
        // Looking straight up/down, use different up
        worldUp = vec3(0.0, 0.0, 1.0);
        right = cross(worldUp, toCam);
        rightLen = length(right);
    }
    right /= rightLen;

    // up = cross(toCam, right)
    vec3 up = cross(toCam, right);

    // Generate billboard vertex position
    vec3 offset = right * corner.x * size + up * corner.y * size;
    vec3 worldPos = iCenter + offset;

    gl_Position = uProjection * uView * vec4(worldPos, 1.0);

    // Extract alpha (inverted: 0-255 -> 1.0-0.0)
    int invertedAlpha = (iAbhsl >> 24) & 0xFF;
    float alpha = 1.0 - float(invertedAlpha) / 255.0;

    // Extract HSL and convert to RGB
    vec3 hsl = vec3(
        float((iAbhsl >> 10) & 63),  // hue (6 bits)
        float((iAbhsl >> 7) & 7),    // saturation (3 bits)
        float(iAbhsl & 127)          // luminance (7 bits)
    );
    vec3 rgb = hslToRgb(hsl);

    vColor = vec4(rgb, alpha);
    // Mask to 16 bits to handle signed short interpretation of values > 32767
    vTextureId = iTex.x & 0xFFFF;

    // Base UV coordinates
    vec2 baseUv = uvCoords[cornerIdx];

    // Extract sprite metadata from iTex.w: (columns << 12) | (rows << 8) | frame
    int spriteMeta = iTex.w;
    int columns = (spriteMeta >> 12) & 0xF;
    int rows = (spriteMeta >> 8) & 0xF;
    int frame = spriteMeta & 0xFF;

    // Default to 1x1 if metadata is missing
    if (columns == 0) columns = 1;
    if (rows == 0) rows = 1;

    // Compute frame position in grid
    int frameCol = frame - (frame / columns) * columns; // frame % columns
    int frameRow = frame / columns;

    // Scale UVs to frame size and offset to frame position
    float uScale = 1.0 / float(columns);
    float vScale = 1.0 / float(rows);
    float uOffset = float(frameCol) * uScale;
    float vOffset = float(frameRow) * vScale;

    vUv = vec2(uOffset + baseUv.x * uScale, vOffset + baseUv.y * vScale);
}
