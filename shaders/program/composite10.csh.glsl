/* Certify the inexpensive rectangle route after native triangle submission.
 * Any missing half, partial face, overlap or conflicting attributes keeps the
 * exact triangle path active for this frame's transparent water exit rays.
 */
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/water_face_cache.glsl"
layout(local_size_x=256) in;
const ivec3 workGroups = ivec3(128,1,1);

bool waterGlassRectangle(int face) {
    if (face < waterTotalFaces || face >= waterTotalFaces + waterGlassSlots) return false;
    if (imageLoad(colorimg5,waterFaceAddress(face,2)).r != waterGlassMask
        || imageLoad(colorimg5,waterFaceAddress(face,3)).r != 0u) return false;
    uint halves = imageLoad(colorimg5,waterFaceAddress(face,12)).r;
    if (halves != 6u && halves != 9u) return false;
    return true;
}

bool waterTriangleSharesCorners(int triangle, int face) {
    uint indices = imageLoad(colorimg5,waterTriangleAddress(triangle,19)).r;
    for (int i = 0; i < 3; ++i) {
        int corner = int((indices >> uint(i * 2)) & 3u);
        uint uv = imageLoad(colorimg5,waterTriangleAddress(triangle,i * 6 + 3)).r;
        uint attributes = imageLoad(colorimg5,waterTriangleAddress(triangle,i * 6 + 4)).r;
        if (uv != imageLoad(colorimg5,waterFaceAddress(face,4 + corner)).r
            || attributes != imageLoad(colorimg5,waterFaceAddress(face,8 + corner)).r) return false;
    }
    return true;
}

void main() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (isEyeInWater != 1 || WATER_REFRACTION_STRENGTH <= 0.0) return;
    int row = imageSize(colorimg5).y - 1;
    uint triangle = gl_GlobalInvocationID.x;
    if (triangle >= min(imageLoad(colorimg5,ivec2(21,row)).r,uint(waterTriangleSlots))) return;
    int face = int(imageLoad(colorimg5,waterTriangleAddress(int(triangle),18)).r) - 1;
    if (!waterGlassRectangle(face) || !waterTriangleSharesCorners(int(triangle),face)) {
        imageAtomicOr(colorimg5,ivec2(24,row),1u);
    }
#endif
}
