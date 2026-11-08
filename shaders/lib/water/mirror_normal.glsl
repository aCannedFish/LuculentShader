// Air-side reflection normal stays separate from the Snell interface normal.
#ifndef LIB_WATER_MIRROR_NORMAL_GLSL
#define LIB_WATER_MIRROR_NORMAL_GLSL
#include "/lib/reflections/bsl_water_surface.glsl"

vec3 waterMirrorNormal(vec3 position) {
    return bslWaterReflectionNormal(position, viewToAbsoluteWorld(position), vec3(0.0, 1.0, 0.0));
}
#endif
