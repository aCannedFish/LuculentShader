// Independent adaptation of CaptTatsu's BSL v7.0p1 water-reflection algorithm.
// Preserve its step growth, four refinements and error radius. A bounded 2%
// guard band continues only opaque edge planes, using current-frame texels.
// Callers supply matching world colour/depth and composite their own sky.
#ifndef LUCULENT_BSL_WATER_REFLECTION
#define LUCULENT_BSL_WATER_REFLECTION

vec4 traceBslWaterReflection(sampler2D scene, sampler2D depths, vec3 origin, vec3 normal,
                           out vec3 receiverPosition) {
    receiverPosition = origin;
    vec3 reflectedDirection = normalize(reflect(normalize(origin), normalize(normal)));
    vec3 stride = reflectedDirection * 1.2;
    vec3 offset = stride;
    int refinements = 0;

    for (int iteration = 0; iteration < 40; ++iteration) {
        vec3 position = origin + offset;
        vec4 clip = gbufferProjection * vec4(position, 1.0);
        if (abs(clip.w) < 1e-7) break;
        vec3 projected = clip.xyz / clip.w * 0.5 + 0.5;
        if (projected.z < 0.0 || projected.z > 1.0
            || any(lessThan(projected.xy, vec2(-0.02)))
            || any(greaterThan(projected.xy, vec2(1.02)))) break;
        vec2 texel = 0.5 / vec2(textureSize(depths, 0));
        vec2 sourceUv = clamp(projected.xy, texel, 1.0 - texel);
        bool extended = any(lessThan(projected.xy, vec2(0.0)))
            || any(greaterThan(projected.xy, vec2(1.0)));

        float depth = textureLod(depths, sourceUv, 0.0).r;
        // Clear depth is not a surface. Keep its reconstruction finite, then
        // reject it before refinement rather than treating the far plane as land.
        vec3 receiver = screenToView(projected.xy, min(depth, 0.999999));
        float radius = 1.1 * pow(length(stride) * pow(length(offset), 0.11), 1.1);
        // A screen occluder can lie behind the reflecting point. The loose
        // search radius must never turn it into a forward reflected receiver.
        if (depth < 0.999999 && dot(receiver - origin, reflectedDirection) > 0.0
            && length(position - receiver) < radius) {
            refinements++;
            if (refinements == 4) {
                vec4 colour = textureLod(scene, sourceUv, 0.0);
                // C6 encodes an observed axis-aligned opaque receiver in
                // this interval. Cutouts, sprites and actors may end at the
                // viewport and cannot establish an off-screen continuation.
                if (extended && (colour.a < 1.0625 || colour.a >= 1.4375)) return vec4(0.0);
                float edge = (1.0 / 0.52) * max(abs(projected.x - 0.5), abs(projected.y - 0.5));
                float coverage = clamp(1.0 - pow(edge, 120.0), 0.0, 1.0);
                receiverPosition = receiver;
                // C6 alpha marks world geometry; zero denotes the sky.
                return vec4(colour.rgb, colour.a > 0.5 ? coverage : 0.0);
            }
            offset -= stride;
            stride *= 0.1;
        }
        stride *= 1.8;
        offset += stride;
    }
    return vec4(0.0);
}

// Callers that do not need the reflected air segment retain the original API.
vec4 traceBslWaterReflection(sampler2D scene, sampler2D depths, vec3 origin, vec3 normal) {
    vec3 receiver;
    return traceBslWaterReflection(scene, depths, origin, normal, receiver);
}

// Match BSL's skylight modulation before blending the SSR confidence.
float bslWaterSkyWeight(float skyLevel) {
    return max(1.25 * skyLevel - 0.25, 0.0);
}

float bslWaterFresnel(float cosine) {
    return 0.01 + 0.99 * pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
}

#endif
