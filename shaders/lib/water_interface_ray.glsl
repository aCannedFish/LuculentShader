/* Finite, perspective-correct screen segments for secondary water rays.
 * The caller supplies the interface orientation, so a sloping stream, a
 * vertical fall and a horizontal pond can reject their own submerged side.
 */
vec2 waterInterfacePixel(vec3 point, vec2 size) {
    vec4 clip = gbufferProjection * vec4(point, 1.0);
    return (clip.xy / clip.w * 0.5 + 0.5) * size;
}

bool waterScreenCrossing(vec3 origin, vec3 ray, vec3 plane, float t, out ivec2 pixel) {
    vec3 probe = origin + ray * t;
    if (probe.z >= -near) return false;
    vec2 size = vec2(textureSize(depthtex1, 0));
    vec2 projected = waterInterfacePixel(probe, size);
    if (any(lessThan(projected, vec2(0.0))) || any(greaterThanEqual(projected, size))) return false;
    pixel = ivec2(projected);
    float depth = texelFetch(depthtex1, pixel, 0).r;
    if (depth >= 0.999999) return false;
    vec3 point = screenToView((vec2(pixel) + 0.5) / size, depth);
    if (point.z < probe.z || dot(point - origin, ray) <= 0.02) return false;
    return dot(point - origin, plane) >= -0.03 && texelFetch(colortex6, pixel, 0).a < 4.5;
}

bool waterScreenHit(vec3 origin, vec3 ray, vec3 plane, int steps, out ivec2 hit) {
    float limit = min(far, 96.0);
    if (ray.z > 0.001) limit = min(limit, (-near * 1.02 - origin.z) / ray.z);
    if (limit <= 0.04) return false;
    // Clip the endpoint before stepping: a ray aimed towards the eye otherwise
    // spends its samples beyond the viewport at nearly zero reciprocal depth.
    vec2 size = vec2(textureSize(depthtex1, 0));
    vec2 start = waterInterfacePixel(origin, size) / size;
    vec2 delta = waterInterfacePixel(origin + ray * limit, size) / size - start;
    vec2 edge = mix(vec2(0.0), vec2(1.0), greaterThanEqual(delta, vec2(0.0)));
    vec2 endFrac = (edge - start) / mix(vec2(1.0), delta, greaterThan(abs(delta), vec2(0.000001)));
    endFrac = mix(vec2(1.0), endFrac, greaterThan(abs(delta), vec2(0.000001)));
    float extent = clamp(min(endFrac.x, endFrac.y), 0.0, 1.0);
    float z0 = -origin.z;
    float z1 = -(origin.z + ray.z * limit);
    float previous = 0.0;
    for (int i = 1; i <= steps; ++i) {
        float u = extent * float(i) / float(steps);
        float t = limit * u * z0 / max(mix(z1, z0, u), 0.0001);
        if (waterScreenCrossing(origin, ray, plane, t, hit)) {
            for (int j = 0; j < 3; ++j) {
                float mid = 0.5 * (previous + t);
                ivec2 refined;
                if (waterScreenCrossing(origin, ray, plane, mid, refined)) {
                    hit = refined;
                    t = mid;
                } else previous = mid;
            }
            return true;
        }
        previous = t;
    }
    return false;
}
