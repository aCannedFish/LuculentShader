// Filter radiance before Fresnel and transmission, using the receiver range
// and the actual water interface as guides. Unknown sky fallback is distinct
// from a completed sky exit. A tiny unsupported hole can borrow only a coherent
// majority of nearby surface hits; large missing regions remain unresolved.
vec3 filterWaterReflection(ivec2 pixel, vec3 position) {
    vec4 centre = texelFetch(colortex15, pixel, 0);
    if (WATER_FILTER_STRENGTH <= 0.0) return centre.rgb;
    ivec2 last = textureSize(colortex15, 0) - 1;
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 sum = centre.rgb * 4.0;
    float total = 4.0;
    vec3 supportedColour = vec3(0.0);
    float supportedWeight = 0.0;
    float minRange = 1e8;
    float maxRange = 0.0;
    int supported = 0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            ivec2 tap = pixel + ivec2(x, y);
            if (any(lessThan(tap, ivec2(0))) || any(greaterThan(tap, last))) continue;
            vec4 water = texelFetch(colortex9, tap, 0);
            if (water.a < 0.5) continue;
            vec2 uv = (vec2(tap) + 0.5) / vec2(last + 1);
            vec3 neighbour = waterSurfacePosition(uv, water.b);
            if (abs(dot(neighbour - position, up)) > 0.06) continue;
            vec4 value = texelFetch(colortex15, tap, 0);
            float weight = x == 0 || y == 0 ? 2.0 : 1.0;
            if (value.a > 0.0) {
                supportedColour += value.rgb * weight;
                supportedWeight += weight;
                minRange = min(minRange, value.a);
                maxRange = max(maxRange, value.a);
                supported++;
            }
            if (centre.a > 0.0 && value.a > 0.0) {
                weight *= exp(-abs(value.a - centre.a) / max(0.15, centre.a * 0.025));
            } else if (!(centre.a < 0.0 && value.a < 0.0)) continue;
            sum += value.rgb * weight;
            total += weight;
        }
    }
    float range = centre.a > 0.0 ? centre.a : length(position);
    float strength = WATER_FILTER_STRENGTH * smoothstep(4.0, 20.0, range);
    vec3 filtered = sum / total;
    if (centre.a < -1.5 && supported >= 6 && maxRange - minRange < max(0.5, minRange * 0.06)) {
        filtered = supportedColour / max(supportedWeight, 0.001);
    }
    return mix(centre.rgb, filtered, strength);
}
