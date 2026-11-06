// Volume resolution.
#ifndef LIB_VOLUME_RESOLUTION_GLSL
#define LIB_VOLUME_RESOLUTION_GLSL

vec2 volumeSize() {
#if VOLUMETRIC_RESOLUTION == 0
    return max(floor(vec2(viewWidth, viewHeight) * 0.25), vec2(1.0));
#else
    return max(floor(vec2(viewWidth, viewHeight) * 0.5), vec2(1.0));
#endif
}
#endif
