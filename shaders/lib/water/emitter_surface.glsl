#ifndef LUCULENT_EMITTER_SURFACE
#define LUCULENT_EMITTER_SURFACE
#include "/lib/water/emitter_layout.glsl"

// A complete same-frame index may validate colour; missing data stays unknown.
bool waterEmittersReady() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    int row = imageSize(colorimg5).y - 1;
    return isEyeInWater == 0 && waterEmitterWords <= waterTriangleWords - waterPlantCells
        && imageLoad(colorimg5, ivec2(17, row)).r == uint(frameCounter) + 1u
        && imageLoad(colorimg5, waterEmitterAddress(1)).r == uint(frameCounter) + 1u
        && imageLoad(colorimg5, waterEmitterAddress(0)).r == 0u
        && imageLoad(colorimg5, ivec2(30, row)).r > 0u;
#else
    return false;
#endif
}

// Fetch the original geometry position relative to the camera cell.
vec3 waterEmitterPosition(int triangle, int vertex) {
    return uintBitsToFloat(uvec3(imageLoad(colorimg5, waterEmitterRecord(triangle, vertex * 3)).r,
        imageLoad(colorimg5, waterEmitterRecord(triangle, vertex * 3 + 1)).r,
        imageLoad(colorimg5, waterEmitterRecord(triangle, vertex * 3 + 2)).r));
}

// Native UVs preserve resource-pack cutouts while testing a finite triangle.
bool waterEmitterOpaque(int triangle, vec3 barycentric) {
    vec2 uv = vec2(0.0);
    for (int vertex = 0; vertex < 3; ++vertex) {
        uv += unpackUnorm2x16(imageLoad(colorimg5, waterEmitterRecord(triangle, 9 + vertex)).r)
            * barycentric[vertex];
    }
    return textureLod(colortex5, uv, 0.0).a >= 0.1;
}

// A source is classified only where a submitted, alpha-valid primitive exists.
// Missing geometry or an exhausted list leaves it unclassified.
bool waterEmitterContains(int triangle, vec3 point, float tolerance) {
    vec3 a = waterEmitterPosition(triangle, 0);
    vec3 e1 = waterEmitterPosition(triangle, 1) - a;
    vec3 e2 = waterEmitterPosition(triangle, 2) - a;
    vec3 normal = cross(e1, e2);
    float area = dot(normal, normal);
    if (area < 1e-16) {
        return false;
    }
    vec3 relative = point - a;
    if (abs(dot(normal, relative)) > tolerance * sqrt(area)) {
        return false;
    }
    float d00 = dot(e1, e1);
    float d01 = dot(e1, e2);
    float d11 = dot(e2, e2);
    vec2 bary = vec2(d11 * dot(relative, e1) - d01 * dot(relative, e2),
                     d00 * dot(relative, e2) - d01 * dot(relative, e1)) / area;
    if (min(bary.x, bary.y) < 0.0 || bary.x + bary.y > 1.0) {
        return false;
    }
    return waterEmitterOpaque(triangle, vec3(1.0 - bary.x - bary.y, bary));
}

// Classify an observation only when current geometry supports its source.
bool waterEmitterPoint(vec3 point, float tolerance) {
    if (!waterEmittersReady()) {
        return false;
    }
    vec3 local = point + vec3(waterFarSize) * 0.5;
    if (any(lessThan(local, vec3(0.0))) || any(greaterThanEqual(local, vec3(waterFarSize)))) {
        return false;
    }
    ivec3 first = clamp(ivec3(floor(local - tolerance)), ivec3(0), waterFarSize - 1);
    ivec3 last = clamp(ivec3(floor(local + tolerance)), ivec3(0), waterFarSize - 1);
    int budget = int(min(imageLoad(colorimg5, ivec2(31, imageSize(colorimg5).y - 1)).r, 128u));
    for (int z = first.z; z <= last.z; ++z) {
        for (int y = first.y; y <= last.y; ++y) {
            for (int x = first.x; x <= last.x; ++x) {
                uint key = waterEmitterCellKey(ivec3(x, y, z));
                uint node = imageLoad(colorimg5, waterEmitterHead(key)).r;
                for (int visit = 0; visit < budget && node != 0u; ++visit) {
                    int index = int(node) - 1;
                    if (index < 0 || index >= waterEmitterNodes) {
                        return false;
                    }
                    int triangle = int(imageLoad(colorimg5, waterEmitterLink(index, 1)).r);
                    if (triangle < 0 || triangle >= waterEmitterCapacity) {
                        return false;
                    }
                    if (imageLoad(colorimg5, waterEmitterLink(index, 2)).r == key
                        && waterEmitterContains(triangle, point, tolerance)) return true;
                    node = imageLoad(colorimg5, waterEmitterLink(index, 0)).r;
                }
            }
        }
    }
    return false;
}
#endif
