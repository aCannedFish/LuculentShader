// Bloom for composite12.
#ifndef LIB_BLOOM_GLSL
#define LIB_BLOOM_GLSL
/* 全局渲染设置。集中定义加载器常量、缓冲格式和可调宏；各程序共享同一组默认值。
 * 游戏内选项由 shaders.properties 分组，用户选择由加载器保存。
 */
#include "/settings.glsl"

/* 加载器输入声明。集中定义相机、时间、天气、光照、深度与视图/阴影矩阵 uniform。
 */
#include "/lib/uniforms.glsl"

/*
================================================================================
 lib/common.glsl —— 通用常量与数学工具
================================================================================
 这里只放"纯函数"：不声明 uniform、不声明 SIMPLE_VARYING、不读写纹理。
 因此这个文件可以被顶点着色器和片元着色器同时安全地 include。

 命名约定（整个项目统一遵守）：
   - 变量、函数：lowerCamelCase
   - 宏（#define）：UPPER_SNAKE_CASE
   - 顶点属性：GLSL 120 兼容程序使用 gl_* 内置属性
   - uniform：不加前缀，直接用 OptiFine 提供的名字
   - SIMPLE_VARYING：v 开头
   - 材质/枚举：MAT_ 开头
================================================================================
*/
#include "/lib/core/common.glsl"

vec2 bloomSize() {
#if BLOOM_RESOLUTION == 0
    return max(floor(vec2(viewWidth, viewHeight) * 0.5), vec2(1.0));
#else
    return vec2(viewWidth, viewHeight);
#endif
}

// 输入为全屏归一化坐标；返回当前泛光视口内的纹理坐标。
vec2 bloomUv(vec2 uv) {
    vec2 size = bloomSize();
    return clamp(uv * size, vec2(0.5), size - 0.5) / vec2(viewWidth, viewHeight);
}

vec3 extractBloom(vec3 color) {
    float brightness = luma(color);
    float knee = max(BLOOM_THRESHOLD * 0.5, 0.001);
    float soft = clamp(brightness - BLOOM_THRESHOLD + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    float energy = min(max(soft, brightness - BLOOM_THRESHOLD), 6.0);
    return color * max(energy, 0.0) / max(brightness, EPSILON);
}

// 半分辨率下覆盖输出像素的四个象限，先提亮部再平均，避免小火把被阈值吞掉。
vec3 prefilterBloom(sampler2D source, vec2 uv) {
#if ENABLE_BLOOM == 0
    return vec3(0.0);
#elif BLOOM_RESOLUTION == 0
    vec2 pixel = 1.0 / vec2(viewWidth, viewHeight);
    vec2 offset = 0.25 / bloomSize();
    vec3 sum = vec3(0.0);
    for (int x = 0; x < 2; x++) {
        for (int y = 0; y < 2; y++) {
            vec2 sampleUv = clamp(uv + (vec2(float(x), float(y)) * 2.0 - 1.0) * offset,
                                  pixel * 0.5, 1.0 - pixel * 0.5);
            sum += extractBloom(texture(source, sampleUv).rgb);
        }
    }
    return sum * 0.25;
#else
    return extractBloom(texture(source, uv).rgb);
#endif
}

// 对称 13 点高斯核的相邻权重配对，借助线性纹理过滤用 7 次读取近似。
// 半径按场景像素定义，不随泛光档位改变；核权重归一化，不额外放大能量。
vec3 filterBloom(sampler2D source, vec2 uv, vec2 axis) {
#if ENABLE_BLOOM == 0
    return vec3(0.0);
#else
    float spacing = min(1.5 * BLOOM_RADIUS * min(viewWidth, viewHeight) / 1080.0, 2.0);
    vec2 stepUv = axis * spacing / vec2(viewWidth, viewHeight);
    vec3 sum = texture(source, bloomUv(uv)).rgb * 0.161003374;
    sum += (texture(source, bloomUv(uv + stepUv * 1.440286351)).rgb
          + texture(source, bloomUv(uv - stepUv * 1.440286351)).rgb) * 0.265537291;
    sum += (texture(source, bloomUv(uv + stepUv * 3.363547460)).rgb
          + texture(source, bloomUv(uv - stepUv * 3.363547460)).rgb) * 0.123133699;
    sum += (texture(source, bloomUv(uv + stepUv * 5.293177779)).rgb
          + texture(source, bloomUv(uv - stepUv * 5.293177779)).rgb) * 0.030827323;
    return sum;
#endif
}
#endif
