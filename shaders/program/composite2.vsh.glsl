#define SIMPLE_VARYING out

in vec3 vaPosition;
in vec4 vaColor;
in vec3 vaNormal;
in vec2 vaUV0;
in ivec2 vaUV2;
uniform vec3 modelOffset;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
#ifdef WATER_TRANSMISSION_PASS
#include "/lib/water_storage_layout.glsl"
layout(r32ui, binding=5) uniform uimage2D colorimg5;
uniform int frameCounter;
uniform int isEyeInWater;
flat out vec3 vGlassLower;
flat out vec3 vGlassUpper;
#endif
void main() {
    gl_Position = vec4(vaPosition.xy * 2.0 - 1.0, 0.0, 1.0);
#ifdef WATER_TRANSMISSION_PASS
    // Bounds are identical for the whole draw. Read the three occupancy
    // words here rather than once for every pixel in the underwater window.
    vGlassLower = vec3(0.0);
    vGlassUpper = vec3(-1.0);
    int row = imageSize(colorimg5).y - 1;
    if (isEyeInWater == 1 && imageLoad(colorimg5, ivec2(17,row)).r == uint(frameCounter) + 1u) {
        uvec3 mask = uvec3(imageLoad(colorimg5, ivec2(18,row)).r,
                           imageLoad(colorimg5, ivec2(19,row)).r,
                           imageLoad(colorimg5, ivec2(20,row)).r);
        if (all(notEqual(mask, uvec3(0u)))) {
            vGlassLower = vec3(findLSB(mask)) * vec3(waterFarSize / 32);
            vGlassUpper = vec3(findMSB(mask) + 1) * vec3(waterFarSize / 32);
        }
    }
#endif
}
