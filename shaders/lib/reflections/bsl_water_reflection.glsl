// Independent adaptation of CaptTatsu's BSL v7.0p1 water-reflection algorithm.
// Preserve its step growth, four refinements, error radius and viewport alpha.
// Callers supply matching world colour/depth and composite their own sky.
#ifndef LUCULENT_BSL_WATER_REFLECTION
#define LUCULENT_BSL_WATER_REFLECTION

vec4 traceBslWaterReflection(sampler2D scene, sampler2D depths, vec3 origin, vec3 normal) {
    vec3 reflectedDirection = normalize(reflect(normalize(origin), normalize(normal)));
    vec3 stride = reflectedDirection * 1.2;
    vec3 offset = stride;
    int refinements = 0;

    for (int iteration = 0; iteration < 40; ++iteration) {
        vec3 position = origin + offset;
        vec4 clip = gbufferProjection * vec4(position, 1.0);
        if (abs(clip.w) < 1e-7) break;
        vec3 projected = clip.xyz / clip.w * 0.5 + 0.5;
        if (any(lessThan(projected, vec3(0.0))) || any(greaterThan(projected, vec3(1.0)))) break;

        float depth = textureLod(depths, projected.xy, 0.0).r;
        vec3 receiver = screenToView(projected.xy, depth);
        float radius = 1.1 * pow(length(stride) * pow(length(offset), 0.11), 1.1);
        if (length(position - receiver) < radius) {
            refinements++;
            if (refinements == 4) {
                vec4 colour = textureLod(scene, projected.xy, 0.0);
                float edge = 2.0 * max(abs(projected.x - 0.5), abs(projected.y - 0.5));
                float coverage = clamp(1.0 - pow(edge, 120.0), 0.0, 1.0);
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

// Match BSL's skylight modulation before blending the SSR confidence.
float bslWaterSkyWeight(float skyLevel) {
    return max(1.25 * skyLevel - 0.25, 0.0);
}

float bslWaterFresnel(float cosine) {
    return 0.01 + 0.99 * pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
}

#endif
