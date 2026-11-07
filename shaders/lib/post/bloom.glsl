// 四级 HDR 泛光。低频层打包到同一附件，各级边界独立钳制。
#ifndef LIB_POST_BLOOM_GLSL
#define LIB_POST_BLOOM_GLSL

vec2 bloomSize() {
#if BLOOM_RESOLUTION == 0
    return max(floor(vec2(viewWidth, viewHeight) * 0.5), vec2(1.0));
#else
    return vec2(viewWidth, viewHeight);
#endif
}

vec2 bloomUv(vec2 uv) {
    vec2 size = bloomSize();
    return clamp(uv * size, vec2(0.5), size - 0.5) / vec2(viewWidth, viewHeight);
}

vec3 extractBloom(vec3 color) {
    float brightness = luma(max(color, vec3(0.0)));
    float knee = max(BLOOM_THRESHOLD * 0.5, 0.001);
    float soft = clamp(brightness - BLOOM_THRESHOLD + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    float energy = min(max(soft, brightness - BLOOM_THRESHOLD), 6.0);
    return color * max(energy, 0.0) / max(brightness, EPSILON);
}

// 先阈值、后平均，保留单纹素光源。高亮限制在提取时执行。
vec3 prefilterBloom(sampler2D source, vec2 uv) {
#if ENABLE_BLOOM == 0
    return vec3(0.0);
#elif BLOOM_RESOLUTION == 0
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 offset = 0.25 / bloomSize();
    vec3 sum = vec3(0.0);
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            vec2 tap = clamp(uv + (vec2(x, y) * 2.0 - 1.0) * offset,
                0.5 / size, 1.0 - 0.5 / size);
            sum += extractBloom(textureLod(source, tap, 0.0).rgb);
        }
    }
    return sum * 0.25;
#else
    return extractBloom(textureLod(source, uv, 0.0).rgb);
#endif
}

// 0 为基础视口；1/2/3 在另一附件打包为 1/2、1/4、1/8 尺寸。
vec4 postBloomRect(int level) {
    vec2 size = bloomSize();
    vec2 halfSize = max(floor(size * 0.5), vec2(1.0));
    vec2 quarterSize = max(floor(size * 0.25), vec2(1.0));
    if (level == 1) {
        return vec4(vec2(0.0), halfSize);
    }
    if (level == 2) {
        return vec4(halfSize.x, 0.0, quarterSize);
    }
    if (level == 3) {
        return vec4(halfSize.x, quarterSize.y, max(floor(size * 0.125), vec2(1.0)));
    }
    return vec4(vec2(0.0), size);
}

int postBloomLevel(vec2 pixel) {
    for (int level = 1; level <= 3; ++level) {
        vec4 rectangle = postBloomRect(level);
        if (all(greaterThanEqual(pixel, rectangle.xy))
            && all(lessThan(pixel, rectangle.xy + rectangle.zw))) {
            return level;
        }
    }
    return 0;
}

vec3 postBloomSample(sampler2D source, vec2 pixel, vec4 rectangle) {
    vec2 valid = clamp(pixel, rectangle.xy + 0.5, rectangle.xy + rectangle.zw - 0.5);
    return textureLod(source, valid / vec2(viewWidth, viewHeight), 0.0).rgb;
}

// 成对双线性采样覆盖 2×2 块；低频层完整覆盖其源足迹，避免跳过细小亮部。
vec3 postBloomDownsample(sampler2D source, vec2 pixel, int level) {
#if ENABLE_BLOOM == 0
    return vec3(0.0);
#else
    vec4 rectangle = postBloomRect(level);
    vec2 sourcePosition = (pixel - rectangle.xy) / rectangle.zw * bloomSize();
    vec2 footprint = bloomSize() / rectangle.zw;
    // 奇数尺寸的实际缩放略大于 2^level；按真实足迹取上整，避免采样间隙吞掉细光源。
    int count = max(int(ceil(max(footprint.x, footprint.y) * 0.5)), 1);
    vec3 sum = vec3(0.0);
    for (int y = 0; y < count; ++y) {
        for (int x = 0; x < count; ++x) {
            vec2 offset = ((vec2(x, y) + 0.5) / float(count) - 0.5) * footprint;
            sum += postBloomSample(source, sourcePosition + offset, postBloomRect(0));
        }
    }
    return sum / float(count * count);
#endif
}

// 归一化 13 点高斯核，利用相邻权重配对将读取次数降为七次。
vec3 postBloomFilter(sampler2D source, vec2 pixel, vec4 rectangle, vec2 axis) {
#if ENABLE_BLOOM == 0
    return vec3(0.0);
#else
    float spacing = min(1.5 * BLOOM_RADIUS * min(viewWidth, viewHeight) / 1080.0, 2.0);
    vec2 stepSize = axis * spacing;
    vec3 sum = postBloomSample(source, pixel, rectangle) * 0.161003374;
    sum += (postBloomSample(source, pixel + stepSize * 1.440286351, rectangle)
        + postBloomSample(source, pixel - stepSize * 1.440286351, rectangle)) * 0.265537291;
    sum += (postBloomSample(source, pixel + stepSize * 3.363547460, rectangle)
        + postBloomSample(source, pixel - stepSize * 3.363547460, rectangle)) * 0.123133699;
    sum += (postBloomSample(source, pixel + stepSize * 5.293177779, rectangle)
        + postBloomSample(source, pixel - stepSize * 5.293177779, rectangle)) * 0.030827323;
    return sum;
#endif
}

// 各层权重和为一，散射只分配光晕宽度，不额外增加总能量倍率。
vec3 postBloomCombine(sampler2D base, sampler2D pyramid, vec2 uv) {
    vec3 nearGlow = postBloomSample(base, uv * bloomSize(), postBloomRect(0));
    vec3 wideGlow = nearGlow * 0.35;
    const float weights[3] = float[3](0.30, 0.22, 0.13);
    for (int level = 1; level <= 3; ++level) {
        vec4 rectangle = postBloomRect(level);
        wideGlow += postBloomSample(pyramid, rectangle.xy + uv * rectangle.zw, rectangle)
            * weights[level - 1];
    }
    return mix(nearGlow, wideGlow, BLOOM_SCATTER);
}
#endif
