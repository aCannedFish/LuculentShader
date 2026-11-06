// Shared optical dependencies. Entry programs own render targets and scheduling.
#ifndef LUCULENT_WATER_PIPELINE
#define LUCULENT_WATER_PIPELINE
#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
const bool colortex6MipmapEnabled = false;
/*
 * Single-scattering volumetric cloud integration with approximate multiple
 * scattering. Main sky clouds render at half resolution; reflections use fewer
 * samples. Empty regions skip lighting and dense rays terminate early. A finite
 * cylindrical horizon bounds grazing rays before any density/noise sampling.
 */
#include "/lib/atmosphere/clouds_water.glsl"

/* The entire uncovered background shares one atmosphere and celestial model. */
#include "/lib/atmosphere/sky_background_water.glsl"

uniform sampler2D colortex4;
/*
 * 水面光学：固定水底采样、按光程衰减的透射、局部散射与 Fresnel 倒影。
 * 倒影在不透明深度上进行透视正确的 DDA，深度约束滤波模拟粗糙度。
 * 未命中/离屏时先用阴影贴图找相机看不到的遮挡物，再退回受当地天光限制的
 * 天空与方块云。
 */
#include "/lib/reflections/water_reflection.glsl"

uniform sampler2D colortex0;
/* 水下光学合成。水上景物随水面波浪扭动，水下前景保持原坐标；
 * 水下几何独立接收光程衰减、模拟焦散与按深度重建的半分辨率光柱。
 */
#include "/lib/water/underwater.glsl"

/* Near-scene media share the existing reduced-resolution volume attachment.
 * Terrain mist is depth-clipped and visibility-bounded; dimension haze reuses
 * the companion's diffuse SH field for soft local glow. Optical-depth blending
 * avoids adding two independent full-strength veils in overlapping air.
 */
#include "/lib/atmosphere/atmosphere_media_water.glsl"

/* Depth-aware reconstruction of the reduced air/cloud field. Callers declare
 * the common depth, water and volume samplers before including this module. */
#include "/lib/atmosphere/volume_reconstruction.glsl"

#endif
