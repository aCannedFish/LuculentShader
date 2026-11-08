// The first volume texel stores native eye-depth metadata for underwater passes.
#ifndef LIB_UNDERWATER_STATE_GLSL
#define LIB_UNDERWATER_STATE_GLSL
float estimateUnderwaterDepth() {
    return texture(colortex4, vec2(0.5) / vec2(viewWidth, viewHeight)).a;
}
#endif
