#include "/lib/conventional_lpv.glsl"
#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
#include "/lib/water_face_cache.glsl"
layout(local_size_x=256) in;
#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
#if COLOURED_VOLUME_SIZE == 32
const ivec3 workGroups = ivec3(384, 1, 1);
#elif COLOURED_VOLUME_SIZE == 48
const ivec3 workGroups = ivec3(384, 1, 1);
#elif COLOURED_VOLUME_SIZE == 64
const ivec3 workGroups = ivec3(512, 1, 1);
#else
const ivec3 workGroups = ivec3(1728, 1, 1);
#endif
#else
const ivec3 workGroups = ivec3(384, 1, 1);
#endif
void main() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    int face = int(gl_GlobalInvocationID.x);
    if (face < waterFaceCount) {
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
