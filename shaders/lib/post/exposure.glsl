// 中心加权对数测光。全屏只在状态纹素执行一次，Bloom 与镜头效果不参与测光。
float postMeterExposure() {
    float sum = 0.0;
    float total = 0.0;
    for (int y = 0; y < 9; ++y) {
        for (int x = 0; x < 16; ++x) {
            vec2 uv = (vec2(x, y) + 0.5) / vec2(16.0, 9.0);
            vec2 centered = uv * 2.0 - 1.0;
            float weight = 0.25 + exp(-dot(centered, centered) * 2.5);
            if (postHandPixel(depthtex0, depthtex2, uv)) {
                continue;
            }
            float luminance = max(luma(textureLod(colortex0, uv, 0.0).rgb), 0.0001);
            sum += clamp(log2(luminance), -10.0, 4.0) * weight;
            total += weight;
        }
    }
    float average = exp2(sum / max(total, EPSILON));
    return clamp(0.18 / max(average, 0.0001), AUTO_EXPOSURE_MIN,
        max(AUTO_EXPOSURE_MAX, AUTO_EXPOSURE_MIN));
}

// 五点中位数过滤中心轮廓变化；焦点响应按秒计算。
float postFocusDistance() {
#if DOF_FOCUS_MODE == 1
    return DOF_FOCUS_DISTANCE;
#else
    float values[5];
    const vec2 offsets[5] = vec2[5](vec2(0.0), vec2(-1.0, 0.0),
        vec2(1.0, 0.0), vec2(0.0, -1.0), vec2(0.0, 1.0));
    for (int i = 0; i < 5; ++i) {
        vec2 uv = vec2(0.5) + offsets[i] * 6.0 / vec2(viewWidth, viewHeight);
        float depth = textureLod(depthtex2, uv, 0.0).r;
        values[i] = depth >= 0.999999 ? far : postLinearDepth(depth);
    }
    for (int i = 1; i < 5; ++i) {
        for (int j = i; j > 0; --j) {
            float low = min(values[j - 1], values[j]);
            values[j] = max(values[j - 1], values[j]);
            values[j - 1] = low;
        }
    }
    return max(values[2], 0.3);
#endif
}

vec4 postUpdateExposureFocus(bool valid) {
    vec4 old = texelFetch(colortex13, ivec2(1, 0), 0);
    float target = 1.0;
#if ENABLE_AUTO_EXPOSURE == 1
    target = postMeterExposure();
#endif
    float exposure = target;
    float focus = postFocusDistance();
    if (valid && old.x > 0.0 && old.y > 0.0) {
        float rate = target < old.x ? 3.0 : 1.0;
        float response = 1.0 - exp(-min(frameTime, 0.25) * rate * AUTO_EXPOSURE_SPEED);
        exposure = exp2(mix(log2(old.x), log2(target), response));
        focus = exp2(mix(log2(old.y), log2(focus), 1.0 - exp(-min(frameTime, 0.25) * 6.0)));
    }
#if ENABLE_AUTO_EXPOSURE == 0
    exposure = 1.0;
#endif
    return vec4(exposure, focus, target, 1.0);
}
