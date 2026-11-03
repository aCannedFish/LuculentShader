// The samplers on units 1 and 2 address the resource pack's PBR atlases
// during composite. Image bindings still refer to the current framebuffer.
#ifndef LUCULENT_WATER_SCREEN_IMAGES
#define LUCULENT_WATER_SCREEN_IMAGES
layout(rgba16f, binding=1) readonly uniform image2D colorimg1;
layout(rgba16f, binding=2) readonly uniform image2D colorimg2;

vec4 waterScreenParameters(vec2 uv) {
    ivec2 size = imageSize(colorimg1);
    vec2 p = clamp(uv * vec2(size) - 0.5, vec2(0.0), vec2(size - 1));
    ivec2 a = ivec2(floor(p));
    ivec2 b = min(a + 1, size - 1);
    vec2 f = fract(p);
    return mix(mix(imageLoad(colorimg1, a), imageLoad(colorimg1, ivec2(b.x, a.y)), f.x),
               mix(imageLoad(colorimg1, ivec2(a.x, b.y)), imageLoad(colorimg1, b), f.x), f.y);
}

// Transparent colour is always paired with the depth of a single raster texel.
vec4 waterScreenLayer(vec2 uv) {
    ivec2 size = imageSize(colorimg2);
    return imageLoad(colorimg2, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1));
}
#endif
