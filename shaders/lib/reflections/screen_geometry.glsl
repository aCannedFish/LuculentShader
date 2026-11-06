// Pixel-centred scene depth and neighbours shared by the reflection solvers.
#ifndef LIB_SCREEN_REFLECTION_GLSL
#define LIB_SCREEN_REFLECTION_GLSL

// Sample pixel centres explicitly; interpolated depth invents silhouette geometry.
vec2 reflectionPixelUv(vec2 uv) {
    vec2 size = vec2(viewWidth, viewHeight);
    return (clamp(floor(uv * size), vec2(0.0), size - 1.0) + 0.5) / size;
}

float reflectionSceneDepth(sampler2D depths, vec2 uv) {
    vec2 pixelUv = reflectionPixelUv(uv);
    float depth = texture(depths, pixelUv).r;
    return depth < 0.999999 ? -screenToView(pixelUv, depth).z : far;
}

// 天空邻居不能充当平面的切线：把它推到极远处，让另一侧被选为较近的邻居。
vec3 reflectionNeighbour(sampler2D depths, vec2 uv) {
    float depth = texture(depths, uv).r;
    if (depth >= 0.999999) {
        return vec3(0.0, 0.0, -1.0e6);
    }
    return screenToView(uv, depth);
}

#endif
