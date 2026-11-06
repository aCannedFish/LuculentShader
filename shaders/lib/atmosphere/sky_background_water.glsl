// Sky background for water.
#ifndef LIB_SKY_BACKGROUND_GLSL
#define LIB_SKY_BACKGROUND_GLSL

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_forward.glsl"

/*
================================================================================
 lib/fog.glsl —— 大气雾 / 水下雾
================================================================================
 为什么需要雾？
   1. 它模拟大气散射：远处的物体因为中间隔着厚厚的空气，对比度下降、
      颜色被天空的颜色"洗掉"。
   2. 它藏住边界：玩家的可视距离是有限的，如果远处物体直接"刷"地消失会
      非常突兀。雾让几何体的尽头自然融入天空。

 本实现不依赖游戏的雾参数，而是自己根据视距（far）算一条曲线，
 这样在游戏里调整渲染距离时表现是一致的、可预期的。
================================================================================
*/
#include "/lib/atmosphere/fog_forward.glsl"

vec3 sceneSkyBackground(vec2 uv) {
    return skyRadiance(skyViewDirection(uv));
}

vec3 fillSkyBackground(vec3 color, vec2 uv, float depth) {
    if (depth >= 0.999999) {
        return sceneSkyBackground(uv);
    }
    return color;
}

// Geometry already contains the original loading-distance fog. Replace only
// its colour contribution, preserving attenuation. After weather blending,
// backgroundTransmission prevents the correction from colouring rain streaks.
vec3 correctSkyFog(vec3 color, vec2 uv, float viewDistance, float backgroundTransmission) {
    if (isEyeInWater != 0) {
        return color;
    }
    float factor = getFogFactor(viewDistance);
    // Nearby surfaces and fully opaque weather have no fog-colour correction.
    // Skip the sky direction, angular lookup and gtexture read for zero weight.
    if (factor <= 0.0 || backgroundTransmission <= 0.0) {
        return color;
    }
    return color + (skyAtmosphereRadiance(skyViewDirection(uv)) - getFogColor())
                 * factor * backgroundTransmission;
}

#endif
