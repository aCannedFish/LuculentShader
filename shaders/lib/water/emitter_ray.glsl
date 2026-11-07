#ifndef LUCULENT_EMITTER_RAY
#define LUCULENT_EMITTER_RAY
#include "/lib/water/emitter_surface.glsl"

bool waterEmitterRayTriangle(int triangle, vec3 origin, vec3 ray, float minimum, float maximum) {
    vec3 a = waterEmitterPosition(triangle, 0);
    vec3 e1 = waterEmitterPosition(triangle, 1) - a;
    vec3 e2 = waterEmitterPosition(triangle, 2) - a;
    vec3 p = cross(ray, e2);
    float determinant = dot(e1, p);
    if (abs(determinant) < 1e-10) {
        return false;
    }
    vec3 relative = origin - a;
    float u = dot(relative, p) / determinant;
    vec3 q = cross(relative, e1);
    float v = dot(ray, q) / determinant;
    float distance = dot(e2, q) / determinant;
    if (u < 0.0 || v < 0.0 || u + v > 1.0 || distance < minimum || distance > maximum) {
        return false;
    }
    return waterEmitterOpaque(triangle, vec3(1.0 - u - v, u, v));
}

// Validate only the finite neighbourhood represented by a cached observation.
// Exhaustion remains unknown and cannot remove its existing radiance.
bool waterEmitterRaySupport(vec3 origin, vec3 ray, vec3 source, float radius, out bool complete) {
    complete = false;
    vec3 halfSize = vec3(waterFarSize) * 0.5;
    vec3 low = max(source - radius, -halfSize);
    vec3 high = min(source + radius, halfSize);
    vec3 inverse = sign(ray) / max(abs(ray), vec3(1e-8));
    vec3 a = (low - origin) * inverse;
    vec3 b = (high - origin) * inverse;
    vec3 entry = min(a, b);
    vec3 exit = max(a, b);
    for (int axis = 0; axis < 3; ++axis) {
        if (abs(ray[axis]) < 1e-8 && (origin[axis] < low[axis] || origin[axis] > high[axis])) {
            return false;
        }
    }
    entry = mix(entry, vec3(-1e8), lessThan(abs(ray), vec3(1e-8)));
    exit = mix(exit, vec3(1e8), lessThan(abs(ray), vec3(1e-8)));
    float cursor = max(0.001, max(entry.x, max(entry.y, entry.z)));
    float limit = min(exit.x, min(exit.y, exit.z));
    if (limit <= cursor) {
        complete = true;
        return false;
    }
    int budget = int(min(imageLoad(colorimg5, ivec2(31, imageSize(colorimg5).y - 1)).r, 128u));
    for (int visit = 0; visit < 64 && cursor < limit; ++visit) {
        vec3 point = origin + ray * (cursor + 0.0001) + halfSize;
        ivec3 cell = clamp(ivec3(floor(point)), ivec3(0), waterFarSize - 1);
        uint key = waterEmitterCellKey(cell);
        uint node = imageLoad(colorimg5, waterEmitterHead(key)).r;
        for (int item = 0; item < budget && node != 0u; ++item) {
            int index = int(node) - 1;
            if (index < 0 || index >= waterEmitterNodes) {
                return false;
            }
            int triangle = int(imageLoad(colorimg5, waterEmitterLink(index, 1)).r);
            if (triangle < 0 || triangle >= waterEmitterCapacity) {
                return false;
            }
            if (imageLoad(colorimg5, waterEmitterLink(index, 2)).r == key
                && waterEmitterRayTriangle(triangle, origin, ray, cursor - 0.0001, limit)) {
                complete = true;
                return true;
            }
            node = imageLoad(colorimg5, waterEmitterLink(index, 0)).r;
        }
        if (node != 0u) {
            return false;
        }
        vec3 border = -halfSize + (vec3(cell) + step(vec3(0.0), ray));
        vec3 next = mix((border - origin) * inverse, vec3(1e8), lessThan(abs(ray), vec3(1e-8)));
        cursor = max(min(next.x, min(next.y, next.z)), cursor + 0.0001);
    }
    complete = cursor >= limit;
    return false;
}
#endif
