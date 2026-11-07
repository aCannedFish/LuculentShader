// 原生分辨率 TAA：无抖动重投影、逐纹素深度拒绝及 YCoCg 方差裁切。
vec3 postToYCoCg(vec3 color) {
    return vec3(dot(color, vec3(0.25, 0.5, 0.25)),
        (color.r - color.b) * 0.5, dot(color, vec3(-0.25, 0.5, -0.25)));
}

vec3 postFromYCoCg(vec3 color) {
    return vec3(color.x + color.y - color.z, color.x + color.z,
        color.x - color.y - color.z);
}

// 逐个检验双线性足迹；轮廓之外的历史不能混入本次插值。
bool postReadHistory(vec2 uv, float expectedDepth, bool sky, bool hand, out vec3 color) {
    ivec2 size = textureSize(colortex13, 0);
    vec2 position = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(position));
    vec2 fraction = fract(position);
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 pixel = base + ivec2(x, y);
            if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))
                || postReservedPixel(pixel)) {
                continue;
            }
            vec4 sampleValue = texelFetch(colortex13, pixel, 0);
            float depth = abs(sampleValue.a);
            bool sameLayer = sky ? depth == 0.0 : depth > 0.0
                && (sampleValue.a < 0.0) == hand
                && abs(depth - expectedDepth) < max(0.08, expectedDepth * 0.015);
            if (!sameLayer || any(isnan(sampleValue)) || any(isinf(sampleValue))) {
                continue;
            }
            vec2 weights = mix(1.0 - fraction, fraction, vec2(x, y));
            float weight = weights.x * weights.y;
            sum += max(sampleValue.rgb, vec3(0.0)) * weight;
            total += weight;
        }
    }
    color = sum / max(total, EPSILON);
    return total > 0.25;
}

vec3 postTemporalResolve(ivec2 pixel, vec2 uv, bool valid, out float storedDepth) {
    float depth = texelFetch(depthtex0, pixel, 0).r;
    bool sky = depth >= 0.999999;
    bool hand = postHandPixel(depthtex0, depthtex2, uv);
    storedDepth = sky ? 0.0 : postLinearDepth(depth) * (hand ? -1.0 : 1.0);
    vec3 centre = max(texelFetch(colortex0, pixel, 0).rgb, vec3(0.0));
#if ENABLE_TAA == 0 || DEBUG_VIEW != 0
    return centre;
#else
    if (!valid) {
        return centre;
    }
    vec3 previous = postPreviousPosition(uv, depth);
    if (hand) {
        previous = vec3(uv, abs(storedDepth));
    }
    if (any(lessThan(previous.xy, vec2(0.0))) || any(greaterThan(previous.xy, vec2(1.0)))) {
        return centre;
    }
    vec3 history;
    if (!postReadHistory(previous.xy, previous.z, sky, hand, history)) {
        return centre;
    }

    ivec2 size = textureSize(colortex0, 0);
    vec3 low = vec3(1e20);
    vec3 high = vec3(-1e20);
    vec3 mean = vec3(0.0);
    vec3 moment = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            ivec2 tap = clamp(pixel + ivec2(x, y), ivec2(0), size - 1);
            vec3 value = max(texelFetch(colortex0, tap, 0).rgb, vec3(0.0));
            value = postToYCoCg(value / (1.0 + luma(value)));
            low = min(low, value);
            high = max(high, value);
            mean += value;
            moment += value * value;
        }
    }
    mean /= 9.0;
    vec3 deviation = sqrt(max(moment / 9.0 - mean * mean, vec3(0.0)));
    vec3 extent = max(deviation * 1.5, (high - low) * 0.05);
    vec3 compressed = history / (1.0 + luma(history));
    vec3 clipped = clamp(postToYCoCg(compressed), max(low, mean - extent), min(high, mean + extent));
    history = max(postFromYCoCg(clipped), vec3(0.0));
    history /= max(1.0 - luma(history), 0.0001);

    float velocity = length((uv - previous.xy) * vec2(size));
    // 以被邻域裁去的历史量判断反应性，子像素覆盖变化仍能正常累积。
    float rejection = length(compressed - postFromYCoCg(clipped));
    float weight = TAA_HISTORY_WEIGHT * exp(-rejection * 8.0) / (1.0 + velocity * 0.04);
    if (texelFetch(colortex9, pixel, 0).a > 0.5) {
        weight = min(weight, 0.75);
    }
    if (hand) {
        weight = min(weight, 0.65);
    }
    // 亮度加权的 HDR 混合抑制极亮样本，历史仍以未经曝光的线性颜色保存。
    float currentWeight = (1.0 - weight) / (1.0 + luma(centre));
    float historyWeight = weight / (1.0 + luma(history));
    return (centre * currentWeight + history * historyWeight) / (currentWeight + historyWeight);
#endif
}
