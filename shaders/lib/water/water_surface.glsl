// Water surface.
#ifndef LIB_WATER_SURFACE_GLSL
#define LIB_WATER_SURFACE_GLSL

/* 水面与积水共用的随机风浪层：带解析导数的值噪声，加上旋转与拉伸。
 * 不依赖任何 uniform，水面（gbuffers_water）与积水（deferred1）都可以直接引用。
 */
#include "/lib/water/wave_noise.glsl"

#include "/lib/water_surface_normal.glsl"

#endif
