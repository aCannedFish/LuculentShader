// Fog for forward.
#ifndef LIB_FOG_GLSL
#define LIB_FOG_GLSL

/* 本文件用到的 uniform（全部在 lib/uniforms.glsl 中声明）：
 *   fogColor        游戏提供的地平线雾颜色（vec3）
 *   far             投影远平面距离 = 渲染距离，自定义雾的基准
 *   skyColor        天空颜色，用来给雾染色
 *   isEyeInWater    0 = 空气，1 = 水，2 = 岩浆，3 = 细雪
 */

/* ---------------------------------------------------------------------------
 * 计算给定距离处的雾浓度
 *   返回 0 = 完全清晰，1 = 完全被雾遮蔽
 * ------------------------------------------------------------------------ */
#include "/lib/fog_medium.glsl"

/* ---------------------------------------------------------------------------
 * 计算雾的颜色。
 *   fogColor 是游戏提供的地平线颜色，随日夜、天气及视线方向变化。
 *   远处地形直接趋向这个颜色，才能与天空边缘接上。
 * ------------------------------------------------------------------------ */
vec3 getFogColor() {
    if (isEyeInWater == 1) {
        // 水下：偏青蓝，并且明显压暗，模拟光线被吸收。
        return vec3(0.08, 0.22, 0.35);
    }
    if (isEyeInWater == 2) {
        return vec3(0.60, 0.15, 0.02);  // 岩浆
    }

    // 游戏的 fogColor 就是地平线颜色，并且已随时间、天气更新。
    // 与天空使用同一输入和转换，避免远处地形出现另一种颜色的色带。
    return dimensionFogColor();
}

/* ---------------------------------------------------------------------------
 * 对外的总入口：对颜色应用雾
 *
 * 参数：
 *   color              已经算完光照的颜色
 *   distanceToCamera   该点到摄像机的直线距离（单位：方块）
 *
 * 返回：混合了雾之后的颜色。
 * ------------------------------------------------------------------------ */
vec3 applyFog(vec3 color, float distanceToCamera) {
    float fogFactor = getFogFactor(distanceToCamera);

    // mix(a, b, t) = a * (1-t) + b * t
    // fogFactor 接近 1 时颜色几乎完全变成雾色。
    return mix(color, getFogColor(), fogFactor);
}

// The migrated renderer preserves unfogged opaque radiance for reflections.
// Deferred applies its camera segment once; later particles/translucency retain
// their forward fog. Stage values come from the fixed J9 RenderStage contract.
vec3 applySurfaceFog(vec3 color, float distanceToCamera) {
    return applyFog(color, distanceToCamera);
}

#endif  // LIB_FOG_GLSL
