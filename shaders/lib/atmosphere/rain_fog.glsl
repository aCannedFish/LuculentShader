// 雨天低层体积雾。复用云噪声体与原生光照体素，不依赖旧配套 Mod。
// 参考 Derivative 的高度衰减和三维密度团，保留本管线的遮挡与积分预算。
#ifndef LIB_RAIN_FOG_GLSL
#define LIB_RAIN_FOG_GLSL
#include "/lib/atmosphere/sky_noise.glsl"

bool nativeRainFogEnabled() {
#if SIMPLE_DIMENSION != 0
    return false;
#else
    return isEyeInWater == 0 && FOG_DENSITY > 0.0
        && weatherRainAmount() * rainBiome * RAIN_FOG_STRENGTH > 0.001;
#endif
}

// 与天空共用 64^3 周期噪声的图集；相邻 Z 切片分别过滤后插值。
vec4 rainFogNoise(vec3 position) {
    vec3 p = fract(position) * 64.0;
    float slice = floor(p.z);
    float nextSlice = mod(slice + 1.0, 64.0);
    vec2 first = vec2(mod(slice, 8.0), floor(slice / 8.0)) * 66.0;
    vec2 second = vec2(mod(nextSlice, 8.0), floor(nextSlice / 8.0)) * 66.0;
    vec2 inside = p.xy + 1.5;
    return mix(texture(noisetex, (first + inside) / 1024.0),
        texture(noisetex, (second + inside) / 1024.0), fract(p.z));
}

float nativeRainFogDensity(vec3 relative) {
    vec3 world = cameraPosition + relative;
    float outdoors = smoothstep(0.03, 0.45, float(eyeBrightnessSmooth.y) / 240.0);
    float altitude = exp2(-max(world.y - RAIN_FOG_ALTITUDE, 0.0) / 16.0);
    if (outdoors <= 0.001) {
        return 0.0;
    }
    float ground = 0.45;
#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
    ivec3 origin = lpvOrigin(cameraPosition);
    ivec3 cell = ivec3(floor(world)) - origin;
    if (lpvInside(cell)) {
        if (lpvOpaque(lpvVoxel(cell))) {
            return 0.0;
        }
        // 仅把已观察的原生地表用于近地增强，未知区域保留稀薄高度雾。
        const int offsets[4] = int[4](1, 3, 6, 10);
        float height = 16.0;
        for (int i = 0; i < 4; ++i) {
            ivec3 below = cell - ivec3(0, offsets[i], 0);
            if (lpvInside(below) && lpvOpaque(lpvVoxel(below))) {
                height = float(offsets[i]);
                break;
            }
        }
        vec3 border = min(vec3(cell), vec3(lpvShape() - 1 - cell));
        float coverage = smoothstep(1.0, 5.0, min(border.x, min(border.y, border.z)));
        ground = mix(ground, 0.35 + 0.65 * exp(-height / 6.0), coverage);
        if (height < 16.0) {
            altitude = mix(altitude, exp(-max(height - 2.0, 0.0) / 6.0), coverage);
        }
    }
#endif
    if (altitude < 0.01) {
        return 0.0;
    }
    float clock = frameTimeCounter * TAU / 3600.0;
    vec3 drift = vec3(sin(clock), 0.0, cos(clock)) * 0.25;
    vec3 coordinate = world / vec3(1024.0, 512.0, 1024.0) + drift;
    float shape = rainFogNoise(coordinate).r * 0.72
        + rainFogNoise(coordinate * 2.0 - drift * 0.35).g * 0.28;
    shape = smoothstep(0.34, 0.70, shape);
    return weatherRainAmount() * clamp(rainBiome, 0.0, 1.0) * RAIN_FOG_STRENGTH
        * shape * ground * altitude * outdoors * FOG_DENSITY * 0.014;
}
#endif
