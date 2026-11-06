// Atmosphere media for water.
#ifndef LIB_ATMOSPHERE_MEDIA_GLSL
#define LIB_ATMOSPHERE_MEDIA_GLSL
/* 近地面日光的单次体积散射。真实阴影限制入射光，Beer-Lambert 同时约束
 * 透射损失与散射增益；复用半分辨率场，不使用屏幕径向模糊或时间随机噪声。
 */
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

/* Outdoor terrain mist. The companion's reserved atlas rows contain ground
 * height, habitat, native sky/block exposure and validity at four-block spacing.
 * No screen-derived height plane is used: missing chunks and indoor columns do
 * not seed fog. Header-relative coordinates survive OptiFine origin rebasing.
 */
#include "/lib/atmosphere/ground_fog.glsl"

bool localAtmosphereEnabled() {
    if (isEyeInWater != 0 || FOG_DENSITY <= 0.0) {
        return false;
    }
#if SIMPLE_DIMENSION == -1
    return NETHER_ATMOSPHERE > 0.0;
#elif SIMPLE_DIMENSION == 1
    return END_ATMOSPHERE > 0.0;
#else
    return groundFogEnabled();
#endif
}

vec4 mergeAtmosphericMedia(vec4 first, vec4 second) {
    if (first.a <= 0.00001) {
        return second;
    }
    if (second.a <= 0.00001) {
        return first;
    }
    float a = -log(max(1.0 - first.a, 0.00001));
    float b = -log(max(1.0 - second.a, 0.00001));
    float opacity = 1.0 - exp(-a - b);
    vec3 source = (first.rgb * a / first.a + second.rgb * b / second.a) / (a + b);
    return vec4(source * opacity, opacity);
}

vec4 integrateLocalAtmosphere(vec2 uv, float sceneDistance) {
    if (!localAtmosphereEnabled()) {
        return vec4(0.0);
    }
    vec3 rayView = normalize(screenToView(uv, 0.5));
    vec3 ray = normalize(mat3(gbufferModelViewInverse) * rayView);
    float range = min(96.0, far * 0.80);
    float limit = min(sceneDistance, range);
    vec3 radiance = vec3(0.0);
    float transmission = 1.0;
    float previous = 0.0;
    vec3 localGlow = vec3(0.0);
    vec4 terrainOrigin = vec4(0.0);
    vec4 terrainMetadata = vec4(0.0);
    vec2 noiseOrigin = cameraPosition.xz;
    if (hasTerrainAtmosphere()) {
        terrainOrigin = terrainFogHeader(0.0);
        terrainMetadata = terrainFogHeader(1.0);
        noiseOrigin = terrainMetadata.yz - terrainOrigin.xy;
    }
    vec3 solar = getSunLightColor() + getMoonLightColor();
    // 阴雨由天空漫射照亮低层雾，云影不再被放大成贯穿视野的明暗光柱。
    solar *= 1.0 - smoothstep(0.15, 0.85, weatherRainAmount());
    float phase = airScatteringPhase(dot(ray, normalize(mat3(gbufferModelViewInverse) * getLightDirView())));
    float directVisibility = 1.0;
    float minimumTransmission = mix(0.45, 0.60,
        clamp(weatherRainAmount() * RAIN_FOG_STRENGTH, 0.0, 1.0));
    for (int index = 0; index < ATMOSPHERE_STEPS; index++) {
        float u = float(index + 1) / float(ATMOSPHERE_STEPS);
        float next = min(u * u * range, limit);
        if (next <= previous || transmission <= minimumTransmission + 0.001) {
            break;
        }
        float distance = (previous + next) * 0.5;
        vec3 relative = ray * distance;
        float density;
        vec3 source;
#if SIMPLE_DIMENSION == 0
        float coverage;
        vec4 field = sampleTerrainFog(relative.xz, terrainOrigin, terrainMetadata, coverage);
        density = terrainMistDensity(relative, field, coverage, noiseOrigin + relative.xz);
        if (density <= 0.000001) {
            previous = next;
            continue;
        }
        vec3 sky = mix(toLinearSpace(skyColor) * 0.40, vec3(0.018, 0.030, 0.050), getNightFactor());
        sky = mix(sky, vec3(luma(sky)) * vec3(0.92, 0.96, 1.0), weatherRainAmount());
        source = sky + twilightIrradiance(vec3(0.0, 1.0, 0.0)) * 0.55;
        if (any(greaterThan(solar, vec3(0.0)))) {
#if ENABLE_SHADOWS == 1
            if (index - (index / 2) * 2 == 0) {
                directVisibility = airSunVisibility(ray, previous, next);
                directVisibility *= sampleAirCloudShadow(colortex3, cameraPosition + relative,
                    normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
            }
#endif
            source += solar * directVisibility * phase * PI * 1.5;
        }
        float block = 4.0 * blockLightAttenuation(field.a) * BLOCK_LIGHT_STRENGTH;
        if (block > 0.001) {
            vec3 tint = toLinearSpace(vec3(1.0, 0.65, 0.32));
#if ENABLE_COLOURED_LIGHTING == 1
            vec3 ground = cameraPosition + vec3(relative.x, field.r + 2.0 - cameraPosition.y, relative.z);
            vec4 hue = companionHue(ground - companionHueOrigin);
            if (hue.a > 0.5) {
                tint = hue.rgb;
            }
#endif
            float height = max(cameraPosition.y + relative.y - field.r, 0.0);
            source += tint * block * exp(-height / 10.0) * 0.35;
        }
#else
        vec2 worldXZ = noiseOrigin + relative.xz;
        float worldY = cameraPosition.y + relative.y;
        float clock = frameTimeCounter * TAU / 3600.0;
        vec2 drift = vec2(sin(clock * 3.0), cos(clock * 3.0)) * 0.6;
        float pockets = atmosphereNoise2(worldXZ / 64.0 + vec2(worldY * 0.018) + drift, 16.0);
#if SIMPLE_DIMENSION == -1
        density = NETHER_ATMOSPHERE * mix(0.0007, 0.0032, pockets) * FOG_DENSITY;
        vec3 lower = mix(dimensionFogColor(), vec3(0.16, 0.035, 0.009), 0.12);
        source = mix(lower, dimensionAmbient(vec3(0.0, 1.0, 0.0)), smoothstep(25.0, 90.0, worldY));
#else
        density = END_ATMOSPHERE * mix(0.0004, 0.0018, pockets) * FOG_DENSITY;
        source = mix(vec3(0.045, 0.020, 0.075), vec3(0.020, 0.060, 0.080), pockets);
#endif
        if (index - (index / 2) * 2 == 0) {
            localGlow = companionIndirect(rayView * distance, -rayView);
        }
        source += localGlow * 0.35;
#endif
        density *= smoothstep(1.5, 6.0, distance)
                 * (1.0 - smoothstep(far * 0.55, far * 0.80, distance));
        float available = log(max(transmission, 0.00001) / minimumTransmission);
        float opticalDepth = min(density * (next - previous), max(available, 0.0));
        float segment = exp(-opticalDepth);
        radiance += transmission * source * (1.0 - segment);
        transmission *= segment;
        previous = next;
    }
    return vec4(radiance, 1.0 - transmission);
}
#endif
