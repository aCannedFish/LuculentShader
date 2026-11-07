// 虚拟 50mm 薄透镜，散焦半径以像素计；近景为负、远景为正。
float postCircleOfConfusion(float depth, float focus) {
    float distance = max(postLinearDepth(min(depth, 0.999999)), 0.1);
    float focalLength = 0.05;
    float diameter = focalLength * focalLength / DOF_APERTURE
        * (distance - focus) / (distance * max(focus - focalLength, 0.05));
    float radius = diameter * viewHeight / 0.024 * 0.5 * DOF_STRENGTH;
    float limit = 20.0 * min(viewWidth, viewHeight) / 1080.0;
    return clamp(radius, -limit, limit);
}

// 同一深度层内的圆盘采样保留焦平面；近景只在自身散焦足迹内参与覆盖。
vec3 postDepthOfField(vec2 uv) {
    vec3 centre = textureLod(colortex0, uv, 0.0).rgb;
#if ENABLE_DOF == 0 || DEBUG_VIEW != 0
    return centre;
#else
    if (postHandPixel(depthtex0, depthtex2, uv)) {
        return centre;
    }
    vec2 size = vec2(viewWidth, viewHeight);
    float focus = texelFetch(colortex13, ivec2(1, 0), 0).y;
    float depth = textureLod(depthtex0, uv, 0.0).r;
    float circle = postCircleOfConfusion(depth, focus);
    float radius = abs(circle);
    float limit = 20.0 * min(viewWidth, viewHeight) / 1080.0;
    // 搜索相邻近景散焦圈，使前景轮廓能向背景自然扩散。
    for (int i = 0; i < 8; ++i) {
        float angle = float(i) * TAU / 8.0;
        vec2 tap = clamp(uv + vec2(cos(angle), sin(angle)) * limit * 0.5 / size,
            0.5 / size, 1.0 - 0.5 / size);
        float nearCircle = postCircleOfConfusion(textureLod(depthtex0, tap, 0.0).r, focus);
        if (nearCircle < -limit * 0.5 && !postHandPixel(depthtex0, depthtex2, tap)) {
            radius = max(radius, -nearCircle);
        }
    }
    if (radius < 0.5) {
        return centre;
    }
#if DOF_QUALITY == 2
    const int samples = 32;
#else
    const int samples = 16;
#endif
    vec3 sum = centre;
    float total = 1.0;
    float distance = postLinearDepth(min(depth, 0.999999));
    for (int i = 0; i < samples; ++i) {
        float angle = float(i) * 2.39996323;
        float tapRadius = sqrt((float(i) + 0.5) / float(samples)) * radius;
        vec2 tap = uv + vec2(cos(angle), sin(angle)) * tapRadius / size;
        if (any(lessThan(tap, 0.5 / size)) || any(greaterThan(tap, 1.0 - 0.5 / size))
            || postHandPixel(depthtex0, depthtex2, tap)) {
            continue;
        }
        float tapDepth = textureLod(depthtex0, tap, 0.0).r;
        float tapCircle = postCircleOfConfusion(tapDepth, focus);
        float tapDistance = postLinearDepth(min(tapDepth, 0.999999));
        float weight;
        if (tapCircle < 0.0 && tapDistance < distance) {
            weight = smoothstep(tapRadius - 0.5, tapRadius + 0.5, -tapCircle);
        } else {
            weight = smoothstep(tapRadius - 0.5, tapRadius + 0.5, abs(circle));
            weight *= smoothstep(distance * 0.98 - 0.03, distance, tapDistance);
        }
        sum += textureLod(colortex0, tap, 0.0).rgb * weight;
        total += weight;
    }
    return sum / total;
#endif
}
