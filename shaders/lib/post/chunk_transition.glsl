// 加载边界采用有限宽度的圆柱形过渡，近景、天空与水下介质不受影响。
// 参考 Complementary 的天空融合；实际天空/云颜色由调用方提供。
#ifndef LIB_CHUNK_TRANSITION_GLSL
#define LIB_CHUNK_TRANSITION_GLSL

float chunkBoundaryFade(float horizontalDistance) {
#if ENABLE_CHUNK_TRANSITION == 0
    return 0.0;
#else
    float edge = max(far - 8.0, 8.0);
    float width = min(CHUNK_TRANSITION_WIDTH, max(far * 0.20, 4.0));
    return smoothstep(max(edge - width, 0.0), edge, horizontalDistance);
#endif
}

// 新区块沿原生加载进度逐渐增加覆盖率；无额外纹理或世界数据。
float chunkFadeThreshold(vec2 pixel) {
    vec2 position = floor(pixel);
#if AA_MODE == 3
    position += float(frameCounter & 7) * vec2(5.588238, 3.117312);
#endif
    return fract(52.9829189 * fract(dot(position, vec2(0.06711056, 0.00583715))));
}
#endif
