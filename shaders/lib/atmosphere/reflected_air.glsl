// Reflected surface radiance traverses air before reaching a water interface.
#ifndef LIB_REFLECTED_AIR_GLSL
#define LIB_REFLECTED_AIR_GLSL
#include "/lib/atmosphere/sky_field.glsl"
#include "/lib/lighting/shadow_filter_forward.glsl"
#include "/lib/atmosphere/air_scattering.glsl"

// Apply the same illuminated air medium along receiver-to-water travel.
// The main view subsequently integrates only water-to-camera travel, so neither
// segment is omitted or counted twice. This is not render-distance edge fog.
vec3 reflectionAirMedium(vec3 radiance, float distance, vec3 viewDirection, vec3 viewOrigin) {
    if (!airScatteringEnabled() || distance <= 0.001) return radiance;
    vec3 sun = getSunDirWorld();
    if (dot(normalize(sunPosition), getLightDirView()) < 0.95) return radiance;
    vec3 origin = viewToWorld(viewOrigin);
    vec3 ray = normalize(mat3(gbufferModelViewInverse) * viewDirection);
    float range = min(64.0, shadowDistance * 0.8);
    float limit = min(distance, range);
    float lowSun = 1.0 - smoothstep(0.10, 0.65, sun.y);
    float coefficient = min(mix(0.0012, 0.0090, lowSun) * SKY_HAZE * FOG_DENSITY
        * AIR_SCATTER_STRENGTH * smoothstep(0.0, 0.08, sun.y), 0.012);
    vec3 sunlight = getSunLightColor() * PI * 1.5
        * (1.0 - smoothstep(0.15, 0.85, weatherRainAmount()));
    float phase = airScatteringPhase(dot(ray, sun));
    const int samples = min(8, max(4, AIR_SCATTER_STEPS / 4));
    vec3 scattered = vec3(0.0);
    float transmission = 1.0;
    float previous = 0.0;
    for (int i = 0; i < samples; ++i) {
        float u = float(i + 1) / float(samples);
        float next = min(u * u * range, limit);
        if (next <= previous) break;
        float midpoint = (previous + next) * 0.5;
        vec3 relative = origin + ray * midpoint;
        float density = airParticleDensity(cameraPosition + relative)
            * (1.0 - smoothstep(range * 0.75, range, midpoint))
            * (1.0 - smoothstep(far * 0.40, far * 0.65, midpoint));
        float segment = exp(-coefficient * density * (next - previous));
        float visibility = 0.0;
        for (int j = 0; j < 2; ++j) {
            vec3 samplePosition = origin + ray * mix(previous, next, (float(j) + 0.5) * 0.5);
            vec4 projected = shadowProjection * shadowModelView * vec4(samplePosition, 1.0);
            vec3 coordinate = distortShadow(projected.xyz / max(projected.w, EPSILON)) * 0.5 + 0.5;
            if (all(greaterThanEqual(coordinate, vec3(0.0))) && all(lessThanEqual(coordinate, vec3(1.0)))) {
                visibility += filteredShadowVisibility(shadowtex1, coordinate.xy, coordinate.z - 0.00015);
            }
        }
        float clouds = sampleAirCloudShadow(colortex3, cameraPosition + relative, sun);
        scattered += transmission * sunlight * phase * (visibility * 0.5) * clouds * 0.90 * (1.0 - segment);
        transmission *= segment;
        previous = next;
    }
    return radiance * transmission + scattered;
}
#endif
