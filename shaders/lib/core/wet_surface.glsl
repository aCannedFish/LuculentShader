// Wet surface.
#ifndef LIB_WET_SURFACE_GLSL
#define LIB_WET_SURFACE_GLSL

/* Outdoor terrain mist. The companion's reserved atlas rows contain ground
 * height, habitat, native sky/block exposure and validity at four-block spacing.
 * No screen-derived height plane is used: missing chunks and indoor columns do
 * not seed fog. Header-relative coordinates survive OptiFine origin rebasing.
 */
#include "/lib/atmosphere/ground_fog.glsl"

/* 水面与积水共用的随机风浪层：带解析导数的值噪声，加上旋转与拉伸。
 * 不依赖任何 uniform，水面（gbuffers_water）与积水（deferred1）都可以直接引用。
 */
#include "/lib/water/wave_noise.glsl"

/* 世界坐标中的雨滴波环。四个邻域滴点使用解析斜率，避免纹理动画的平铺和跳帧。
 * 半径小于胞元的一半，四邻域足够覆盖；像素足迹过大时连续退出。
 */
#include "/lib/weather/rain_ripples.glsl"

vec2 wetGroundCoverage(vec3 relative, vec3 normalWorld, float skyLight,
                      float kind, float footprint) {
    float wet = weatherGroundWetness() * RAIN_PUDDLES_STRENGTH * float(ENABLE_RAIN_PUDDLES);
    if (wet <= 0.001 || normalWorld.y <= 0.96 || (kind > 0.5 && kind < 5.5) || kind > 9.5) {
        return vec2(0.0);
    }
    float exposure = smoothstep(0.95, 0.995, lightmapLevel(skyLight));
    if (exposure <= 0.001) {
        return vec2(0.0);
    }
    if (hasTerrainAtmosphere()) {
        float coverage;
        vec4 field = sampleTerrainFog(relative.xz, terrainFogHeader(0.0), terrainFogHeader(1.0), coverage);
        float roof = 1.0 - smoothstep(1.2, 3.0, field.r - (cameraPosition.y + relative.y));
        exposure *= mix(1.0, roof, coverage);
    }
    vec2 world = atmosphereWorldXZ(relative.xz);
    float broad = cloudWeatherNoise(world * 0.18);
    float detail = cloudWeatherNoise(world * 0.47 + vec2(31.7, 9.1));
    float height = broad * 0.72 + detail * 0.28;
    float threshold = mix(0.86, 0.53, wet);
    float edge = 0.035 + min(footprint * 0.15, 0.12);
    float puddle = smoothstep(threshold - edge, threshold + edge, height) * wet * exposure;
    return vec2(wet * exposure, puddle);
}

// 积水中的轻微风雨扰动，雨停后逐渐平静；像素无法分辨的短波平滑消退。
// 与水面相同使用两层随机噪声而不是正弦，远处积水不再出现规则条纹。
vec3 wetSurfaceNormal(vec3 normalView, vec3 relative, float coverage, float footprint) {
    if (coverage <= 0.001 || weatherRainAmount() <= 0.001) {
        return normalView;
    }
    vec2 world = atmosphereWorldXZ(relative.xz);
    float time = frameTimeCounter;
    vec2 slope = waterWaveOctave(world, time, 0.52, 1.7, 1.5, 0.8, 0.035,
                                 vec2(5.3, -12.1), footprint);
    slope += waterWaveOctave(world, time, -0.61, 0.85, 1.3, 0.6, 0.012,
                             vec2(-37.7, 21.4), footprint);
    slope += rainRippleSlope(world, time, footprint);
    vec3 ripple = mat3(gbufferModelView) * vec3(-slope.x, 0.0, -slope.y);
    return normalize(normalView + ripple * coverage * weatherRainAmount());
}

#endif
