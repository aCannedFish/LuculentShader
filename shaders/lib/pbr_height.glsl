// Walk the sprite's height field with explicit gradients and clip to its own UV rectangle.
vec2 pbrHeightUv(sampler2D normalAtlas, vec2 uv, vec3 viewTangent, vec4 tile, vec2 du, vec2 dv) {
#if POM_QUALITY == 0
    return uv;
#else
    if (viewTangent.z <= 0.08) return uv;
    float initialDepth = 1.0 - textureGrad(normalAtlas, uv, du, dv).a;
    if (initialDepth < 0.5 / 255.0) return uv;
#if POM_QUALITY == 1
    const int steps = 8;
#elif POM_QUALITY == 2
    const int steps = 16;
#else
    const int steps = 24;
#endif
    vec2 pixel = 0.5 / vec2(textureSize(normalAtlas, 0));
    vec2 minimum = tile.xy - tile.zw + pixel;
    vec2 maximum = tile.xy + tile.zw - pixel;
    vec2 direction = viewTangent.xy / viewTangent.z * tile.zw * 0.5;
    vec2 current = uv;
    vec2 previous = uv;
    float previousDifference = -initialDepth;
    float difference = previousDifference;
    for (int index = 1; index <= steps; index++) {
        float depth = float(index) / float(steps);
        vec2 candidate = uv - direction * depth;
        if (any(lessThan(candidate, minimum)) || any(greaterThan(candidate, maximum))) return current;
        previous = current;
        previousDifference = difference;
        current = candidate;
        difference = depth - (1.0 - textureGrad(normalAtlas, current, du, dv).a);
        if (difference >= 0.0) break;
    }
    float weight = clamp(difference / max(difference - previousDifference, 0.00001), 0.0, 1.0);
    return mix(current, previous, weight);
#endif
}
