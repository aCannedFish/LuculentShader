#include "/lib/conventional_lpv.glsl"
#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
#include "/lib/water_face_cache.glsl"
#include "/lib/water_plant_surface.glsl"
#include "/lib/water_environment_layout.glsl"
#include "/lib/water_entity_triangles.glsl"
layout(local_size_x=256) in;
// Cover all 196608 opaque face slots, or the larger 96-cell lighting volume.
#if (ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0) && COLOURED_VOLUME_SIZE == 96
const ivec3 workGroups = ivec3(1728, 1, 1);
#else
const ivec3 workGroups = ivec3(768, 1, 1);
#endif
void main() {
#if SIMPLE_DIMENSION == 0
    int face = int(gl_GlobalInvocationID.x);
    if (isEyeInWater == 0 && face < waterEnvironmentPixels) {
        ivec2 cell = ivec2(face % waterEnvironmentSide, face / waterEnvironmentSide);
        imageStore(colorimg5, waterEnvironmentAddress(cell, frameCounter & 1, 0), uvec4(floatBitsToUint(65505.0)));
    }
    if (isEyeInWater != 1 && face < waterPlantCells / 2) {
        imageStore(colorimg5, waterPlantAddress(face), uvec4(0u));
        imageStore(colorimg5, waterPlantAddress(face + waterPlantCells / 2), uvec4(0u));
    }
    if (face == 0) imageStore(colorimg5, ivec2(25, imageSize(colorimg5).y - 1), uvec4(uint(frameCounter) + 1u));
#endif
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (face == 0) {
        int row = imageSize(colorimg5).y - 1;
        imageStore(colorimg5, ivec2(28, row), uvec4(uint(frameCounter) + 1u));
        imageStore(colorimg5, ivec2(29, row), uvec4(0u));
    }
    if (face < 4) imageStore(colorimg5, ivec2(21 + face, imageSize(colorimg5).y - 1), uvec4(0u));
    if (isEyeInWater == 1 && face < waterMacroCount) imageStore(colorimg5, waterTriangleHead(face), uvec4(0u));
    if (face < waterLargeColumns) imageStore(colorimg5, waterGlassColumn(face), uvec4(0u));
    if (face < 3) imageStore(colorimg5, ivec2(18 + face, imageSize(colorimg5).y - 1), uvec4(0u));
    if (face < waterColumnCount) imageStore(colorimg5, waterColumnAddress(face), uvec4(0));
    if (face < waterMacroCount) imageStore(colorimg5, waterMacroAddress(face), uvec4(0u));
    if (face < waterFarSlots) imageStore(colorimg5, waterKeyAddress(face), uvec4(0u));
    if (isEyeInWater == 1 && face < waterGlassSlots) {
        int record = waterTotalFaces + face;
        imageStore(colorimg5, waterGlassKeyAddress(face), uvec4(0u));
        imageStore(colorimg5, waterFaceAddress(record,12), uvec4(0u));
        for (int word = 0; word < 4; ++word) imageStore(colorimg5, waterFaceAddress(record, word), uvec4(0u));
    }
    if (face < waterTotalFaces) {
        for (int word = 0; word < 4; ++word) imageStore(colorimg5, waterFaceAddress(face, word), uvec4(0u));
    }
    if (face == 0) imageStore(colorimg5, ivec2(17, imageSize(colorimg5).y - 1), uvec4(uint(frameCounter) + 1u));
#endif
#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
    int index = int(gl_GlobalInvocationID.x);
    ivec2 size = imageSize(colorimg5);
    ivec2 pixel = ivec2(index % size.x, index / size.x);
    ivec3 shape = lpvShape();
    int cells = shape.x * shape.y * shape.z;
    if (all(lessThan(pixel, size)) && index < cells) {
        imageStore(colorimg5, pixel, uvec4(0u));
        imageStore(colorimg5, pixel + ivec2(0, cells / size.x), uvec4(0u));
    }
#endif
}
