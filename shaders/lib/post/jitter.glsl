// 八相位、零均值的子像素采样；原生矩阵出口供无抖动的运动重投影使用。
#ifndef LIB_POST_JITTER_GLSL
#define LIB_POST_JITTER_GLSL

vec2 postJitter(int frame) {
#if AA_MODE == 3 && DEBUG_VIEW == 0
    const vec2 sequence[8] = vec2[8](
        vec2(0.0, -1.0 / 3.0), vec2(-0.5, 1.0 / 3.0),
        vec2(0.5, -7.0 / 9.0), vec2(-0.75, -1.0 / 9.0),
        vec2(0.25, 5.0 / 9.0), vec2(-0.25, -5.0 / 9.0),
        vec2(0.75, 1.0 / 9.0), vec2(0.0, 7.0 / 9.0)
    );
    return sequence[frame & 7] * 0.5 / max(vec2(viewWidth, viewHeight), vec2(1.0));
#else
    return vec2(0.0);
#endif
}

mat4 postRawProjection() {
    return gbufferProjection;
}

mat4 postRawProjectionInverse() {
    return gbufferProjectionInverse;
}

// P' = J P；逆矩阵为 P^-1 J^-1，适用于透视和非对称投影。
mat4 postProjection() {
    mat4 matrix = gbufferProjection;
    vec2 offset = postJitter(frameCounter) * 2.0;
    for (int column = 0; column < 4; ++column) {
        matrix[column].xy += offset * matrix[column].w;
    }
    return matrix;
}

mat4 postProjectionInverse() {
    mat4 matrix = gbufferProjectionInverse;
    vec2 offset = postJitter(frameCounter) * 2.0;
    matrix[3] -= matrix[0] * offset.x + matrix[1] * offset.y;
    return matrix;
}

vec4 postJitterPosition(vec4 clip) {
    clip.xy += postJitter(frameCounter) * (2.0 * clip.w);
    return clip;
}

#define gbufferProjection postProjection()
#define gbufferProjectionInverse postProjectionInverse()
#endif
