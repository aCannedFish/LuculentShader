// Raster water access shared by reflection and transmission stages.
// Return layout: encoded normal RG, native sky exposure B, linear view depth A.
#ifndef LIB_WATER_SURFACE_ACCESS_GLSL
#define LIB_WATER_SURFACE_ACCESS_GLSL
#include "/lib/water_screen_images.glsl"

vec4 waterSurfaceAtPixel(sampler2D geometry, ivec2 pixel) {
    vec4 surface = texelFetch(geometry, pixel, 0);
    if (surface.a < 0.5) return vec4(0.0);
    return vec4(surface.rg, imageLoad(colorimg1, pixel).r, surface.b);
}

vec3 waterSurfacePosition(vec2 uv, float linearDepth) {
    vec4 ray = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    return ray.xyz * (linearDepth / max(-ray.z, EPSILON));
}
#endif
