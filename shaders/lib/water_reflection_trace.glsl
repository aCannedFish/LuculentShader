// Traverse the finite reflected segment in screen space, using the existing
// conservative depth hierarchy. Only a pixel-supported surface returns colour.
// Exhausted budgets and viewport exits stay unknown for the other scene views.
ScreenReflectionHit traceWaterImageDetailed(sampler2D scene, sampler2D depths, vec3 origin,
    vec3 direction, float minimum, float maximum, int budget, vec4 clipPlane) {
    vec3 start = origin + direction * minimum;
    if (start.z >= -near || maximum <= minimum) {
        return screenReflectionHit(vec4(0.0), 0.0, false);
    }
    vec2 uv = waterProjectPixel(start, vec2(1.0));
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) {
        return screenReflectionHit(vec4(0.0), 0.0, false);
    }
    WaterRayHit transparent;
    int visits = clamp(budget * 2, 32, 112);
    WaterRayHit hit = traceWaterGeometry(uv, start, direction, maximum - minimum,
        depths, false, true, visits, clipPlane, transparent);
    if (hit.distance <= 0.0) {
        // Only a completed, unoccluded interval can certify this sky exit.
        // Viewport and budget exits keep their unknown status for reconstruction.
        return screenReflectionHit(vec4(0.0), hit.hidden ? 0.0 : 1.0, false);
    }
    vec2 edge = min(hit.uv, vec2(1.0) - hit.uv);
    float confidence = smoothstep(0.0, 0.02, min(edge.x, edge.y));
    return screenReflectionHit(vec4(hit.uv, hit.distance + minimum, 1.0),
        confidence, !hit.hidden);
}
