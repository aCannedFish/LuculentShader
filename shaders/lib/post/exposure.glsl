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
    float night = 0.0;
    float rain = 0.0;
#if SIMPLE_DIMENSION == 0
    vec3 sun = safeNormalize(mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0));
    night = 1.0 - smoothstep(-0.16, 0.12, sun.y);
    rain = clamp(rainStrength, 0.0, 1.0);
#endif
    // 中灰按当前曲线的输入标定；ACES 拟合自带预曝光，输入 0.18 会偏亮。
    // 以下输入分别映射到约 0.18 的显示线性亮度，EXPOSURE 仍是用户补偿。
#if TONEMAP_MODE == 1
    const float daylightKey = 0.13017;
#elif TONEMAP_MODE == 2
    const float daylightKey = 0.21951;
#else
    const float daylightKey = 0.18;
#endif
    // 在 EV 空间只补偿四分之三，保留受光与遮阴环境的亮度差异。
    // 雨夜继续采用较低目标及独立上限，不把暗场抬成白天。
    float key = mix(daylightKey, 0.035, night) * mix(1.0, 0.70, rain);
    float compensation = exp2(log2(key / max(average, 0.0001)) * 0.75);
    float maximum = mix(AUTO_EXPOSURE_MAX, min(AUTO_EXPOSURE_MAX, AUTO_EXPOSURE_NIGHT_MAX), night);
    maximum = mix(maximum, min(maximum, AUTO_EXPOSURE_RAIN_MAX), rain);
    return clamp(compensation, AUTO_EXPOSURE_MIN,
        max(maximum, AUTO_EXPOSURE_MIN));
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
    float targetEv = log2(target);
    float filteredEv = targetEv;
    float exposure = target;
    float focus = postFocusDistance();
    if (valid && old.x > 0.0 && old.y > 0.0) {
        // 测光目标先低通，再以有限档数/秒接近目标；长帧不瞬间追赶曝光。
        float elapsed = clamp(frameTime, 0.0, 0.05);
        float response = 1.0 - exp(-elapsed * 2.0 * AUTO_EXPOSURE_SPEED);
        filteredEv = mix(old.z, targetEv, response);
        float previousEv = log2(old.x);
        float rate = filteredEv < previousEv ? 1.5 : 0.75;
        float limit = elapsed * rate * AUTO_EXPOSURE_SPEED;
        exposure = exp2(previousEv + clamp(filteredEv - previousEv, -limit, limit));
        focus = exp2(mix(log2(old.y), log2(focus), 1.0 - exp(-elapsed * 6.0)));
#if ENABLE_AUTO_EXPOSURE == 1
        // 短促电光保留真实峰值，不让自动曝光追逐闪光并在随后压暗环境。
        if (lightningPulse(lightningState()) > 0.015) {
            exposure = old.x;
            filteredEv = old.z;
        }
#endif
    }
#if ENABLE_AUTO_EXPOSURE == 0
    exposure = 1.0;
    filteredEv = 0.0;
#endif
    return vec4(exposure, focus, filteredEv, POST_CAMERA_SIGNATURE);
}
