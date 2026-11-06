// Compile only the current dimension's environment; surface and optics share it.
#ifndef LIB_DIMENSION_GLSL
#define LIB_DIMENSION_GLSL

#include "/lib/core/color_space.glsl"
#include "/lib/atmosphere/atmosphere_noise.glsl"

#if SIMPLE_DIMENSION == -1
#include "/lib/dimensions/nether.glsl"
#elif SIMPLE_DIMENSION == 1
#include "/lib/dimensions/end.glsl"
#else
#include "/lib/dimensions/overworld.glsl"
#endif

#endif
