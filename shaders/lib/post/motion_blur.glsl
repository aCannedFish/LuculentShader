// 相机快门积分，按原生深度限制跨层取色。动态实体仍依靠 TAA 的颜色拒绝。
vec3 postMotionBlur(vec2 uv) {
    vec3 centre = textureLod(colortex0, uv, 0.0).rgb;
#if ENABLE_MOTION_BLUR == 0 || DEBUG_VIEW != 0
    return centre;
#else
    vec4 state = texelFetch(colortex13, ivec2(3, 0), 0);
    if (state.w < 0.5 || postHandPixel(depthtex0, depthtex2, uv)) {
        return centre;
    }
    float depth = textureLod(depthtex0, uv, 0.0).r;
    vec3 previous = postPreviousPosition(uv, depth);
    if (previous.z <= 0.0) {
        return centre;
    }
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 velocity = (uv - previous.xy) * size * MOTION_BLUR_SHUTTER;
    float radius = length(velocity);
    if (radius < 0.5) {
        return centre;
    }
    velocity *= min(1.0, MOTION_BLUR_MAX_RADIUS * min(viewWidth, viewHeight) / 1080.0 / radius);
    vec3 sum = centre;
    float total = 1.0;
    float distance = postLinearDepth(min(depth, 0.999999));
    for (int i = 0; i < 8; ++i) {
        float offset = (float(i) + 0.5) / 8.0 - 0.5;
        vec2 tap = uv + velocity * offset / size;
        if (any(lessThan(tap, 0.5 / size)) || any(greaterThan(tap, 1.0 - 0.5 / size))
            || postHandPixel(depthtex0, depthtex2, tap)) {
            continue;
        }
        float tapDepth = textureLod(depthtex0, tap, 0.0).r;
        bool sky = depth >= 0.999999;
        if (sky != (tapDepth >= 0.999999)) {
            continue;
        }
        float difference = abs(postLinearDepth(min(tapDepth, 0.999999)) - distance);
        float weight = sky ? 1.0 : 1.0 - smoothstep(0.05, max(0.1, distance * 0.08), difference);
        sum += textureLod(colortex0, tap, 0.0).rgb * weight;
        total += weight;
    }
    return sum / total;
#endif
}
