// BSL-inspired surface appearance, independent of the refracting interface.
// Five counter-moving noise bands, distant waves and the small normal bump
// follow BSL v7.0p1. Procedural lattice values replace its default noise image;
// Luculent's noisetex is a cloud/lunar atlas and must not be sampled as noise.
#ifndef LUCULENT_BSL_WATER_SURFACE
#define LUCULENT_BSL_WATER_SURFACE
#include "/lib/water/wave_noise.glsl"

float bslWaterWaveNoise(vec2 position) {
    vec2 cell = floor(position);
    vec2 inside = fract(position);
    float a = waterNoiseHash(mod(cell, 256.0));
    float b = waterNoiseHash(mod(cell + vec2(1.0, 0.0), 256.0));
    float c = waterNoiseHash(mod(cell + vec2(0.0, 1.0), 256.0));
    float d = waterNoiseHash(mod(cell + vec2(1.0), 256.0));
    return mix(mix(a, b, inside.x), mix(c, d, inside.x), inside.y);
}

float bslWaterWaveBands(vec2 position, float height, float time, bool distant) {
    const float frequency[5] = float[5](1.1, 1.5, 2.5, 5.0, 8.0);
    const float amplitude[5] = float[5](1.0, 0.8, -0.6, 0.4, -0.2);
    float value = 0.0;
    for (int band = 0; band < 5; ++band) {
        float rate = distant ? (band == 4 ? 2.0 : frequency[band] * 0.2) : frequency[band];
        float direction = (band & 1) == 0 ? 1.0 : -1.0;
        float heightDirection = band == 2 || band == 4 ? 1.0 : -1.0;
        vec2 offset = vec2(direction * time * (distant ? 1.0 : 0.5)
            + heightDirection * height * (distant ? 0.1 : 0.2));
        value += amplitude[band] * bslWaterWaveNoise((position + offset) * (rate * 0.25) - 0.5);
    }
    return value * (distant ? 4.0 : 1.0);
}

float bslWaterWaveHeight(vec2 position, float height, float time, float distance) {
    float blend = clamp(distance / 64.0 - 0.125, 0.0, 1.0);
    float value = 0.0;
    if (blend < 1.0) value += bslWaterWaveBands(position, height, time, false) * (1.0 - blend);
    if (blend > 0.0) value += bslWaterWaveBands(position, height, time, true) * blend;
    return value;
}

// Derive only the reflection/highlight normal. Mesh height, C9 geometry and
// all Snell normals remain on their existing shared height field.
vec3 bslWaterReflectionNormal(vec3 viewPosition, vec3 world, vec3 baseWorld) {
    vec3 base = normalize(baseWorld);
#if ENABLE_WATER_WAVES == 0
    return mat3(gbufferModelView) * base;
#else
    vec3 tangent = abs(base.y) > 0.9 ? normalize(vec3(1.0, 0.0, 0.0) - base * base.x)
        : normalize(cross(vec3(0.0, 1.0, 0.0), base));
    vec3 bitangent = cross(tangent, base);
    vec2 position = vec2(dot(world, tangent), dot(world, bitangent));
    float height = dot(world, base);
    float distance = length(viewPosition);
    float delta = 0.1 * (1.0 + 0.015 * distance);
    vec2 slope = vec2(
        bslWaterWaveHeight(position + vec2(delta, 0.0), height, frameTimeCounter, distance)
            - bslWaterWaveHeight(position - vec2(delta, 0.0), height, frameTimeCounter, distance),
        bslWaterWaveHeight(position + vec2(0.0, delta), height, frameTimeCounter, distance)
            - bslWaterWaveHeight(position - vec2(0.0, delta), height, frameTimeCounter, distance)) / delta;
    float facing = dot(mat3(gbufferModelView) * base, -normalize(viewPosition));
    slope *= pow(max(distance, 4.0), -0.25) * clamp(facing * 4.0, 0.0, 1.0);
    float strength = 0.03 * WATER_WAVE_STRENGTH / 1.5;
    vec3 normal = tangent * slope.x * strength + bitangent * slope.y * strength
        + base * (1.0 - dot(slope, slope) * strength);
    return mat3(gbufferModelView) * normalize(normal);
#endif
}

// Use BSL's 128/192/255 palette and 0.25 surface blend as a chroma grade.
// Preserve lit luminance: this changes surface colour without another
// absorption layer or a change to the already solved refraction.
vec3 bslWaterSurfaceColour(vec3 colour) {
    const vec3 luminance = vec3(0.299, 0.587, 0.114);
    vec3 palette = pow(vec3(128.0, 192.0, 255.0) / 255.0, vec3(4.4));
    vec3 tint = palette * (dot(colour, luminance) / dot(palette, luminance));
    return mix(colour, tint, 0.25);
}
#endif
