// Bracket a single screen-depth crossing before accepting a reflected image.
// A refinement count accumulated across unrelated surfaces is not convergence.
// Failed or off-screen crossings remain unknown for the scene environment.
vec3 waterReflectionProbe(sampler2D scene, sampler2D depths, vec3 point, vec4 clipPlane) {
    if (point.z >= -near) return vec3(-1.0);
    vec4 clip = gbufferProjection * vec4(point, 1.0);
    vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return vec3(-1.0);
    ivec2 size = textureSize(depths, 0);
    ivec2 pixel = ivec2(uv * vec2(size));
    float depth = texelFetch(depths, pixel, 0).r;
    if (depth >= 0.999999 || texelFetch(scene, pixel, 0).a >= 4.5) return vec3(uv, 0.0);
    vec3 surface = screenToView((vec2(pixel) + 0.5) / vec2(size), depth);
    if (dot(clipPlane.xyz, surface) + clipPlane.w < 0.0) return vec3(uv, 0.0);
    return vec3(uv, -surface.z);
}

ScreenReflectionHit traceWaterImageDetailed(sampler2D scene, sampler2D depths, vec3 origin,
    vec3 direction, float minimum, float maximum, int budget, vec4 clipPlane) {
    float stride = max(0.01, length(origin) / max(viewHeight, 1.0));
    float previous = minimum;
    float distance = minimum;
    bool previousFront = true;
    bool visibleSkyExit = false;
    vec2 size = vec2(textureSize(depths, 0));
    for (int step = 0; step < 96; ++step) {
        if (step >= budget || distance >= maximum) break;
        distance = min(distance + stride, maximum);
        vec3 point = origin + direction * distance;
        vec3 sampleValue = waterReflectionProbe(scene, depths, point, clipPlane);
        if (sampleValue.x < 0.0) break;
        bool front = sampleValue.z <= 0.0 || -point.z < sampleValue.z;
        visibleSkyExit = distance >= maximum && sampleValue.z == 0.0;
        if (!front && previousFront) {
            float low = previous;
            float high = distance;
            // Refine this one interval; a different depth discontinuity cannot
            // inherit the convergence state of a previous receiver.
            for (int refinement = 0; refinement < 12; ++refinement) {
                float middle = 0.5 * (low + high);
                vec3 testPoint = origin + direction * middle;
                vec3 test = waterReflectionProbe(scene, depths, testPoint, clipPlane);
                if (test.z > 0.0 && -testPoint.z >= test.z) high = middle;
                else low = middle;
            }
            vec3 hitPoint = origin + direction * high;
            vec3 hit = waterReflectionProbe(scene, depths, hitPoint, clipPlane);
            if (hit.z > 0.0) {
                vec2 pixelUv = (floor(hit.xy * size) + 0.5) / size;
                vec3 receiver = screenToView(pixelUv, texelFetch(depths, ivec2(pixelUv * size), 0).r);
                float cone = max(0.003, hit.z * 2.0 * abs(gbufferProjectionInverse[1][1]) / size.y);
                float along = dot(receiver - origin, direction);
                float error = length(receiver - origin - direction * along);
                if (along > minimum && along < maximum && error <= cone * 1.5
                    && reflectionSurfaceFacesRay(scene, depths, pixelUv, direction)) {
                    vec2 edge = min(hit.xy, 1.0 - hit.xy);
                    float confidence = smoothstep(0.0, 0.02, min(edge.x, edge.y));
                    return screenReflectionHit(vec4(hit.xy, high, 1.0), confidence, true);
                }
            }
            // The crossing was a silhouette without depth support. Advance
            // through it; never widen its colour across an arbitrary thickness.
        }
        previous = distance;
        previousFront = front;
        stride *= 1.7;
    }
    return screenReflectionHit(vec4(0.0), visibleSkyExit ? 1.0 : 0.0, false);
}
