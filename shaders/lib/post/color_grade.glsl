// 白平衡在 HDR 空间调整，先后统一亮度，避免温度滑块同时改变曝光。
vec3 postWhiteBalance(vec3 color) {
    vec3 balance = exp2(vec3(0.18, 0.02, -0.18) * WHITE_BALANCE);
    vec3 result = color * balance;
    return result * luma(color) / max(luma(result), EPSILON);
}

// 保持亮度的冷暗暖亮分离，配合肩部压缩形成较柔和的电影调色。
vec3 postColorGrade(vec3 color) {
#if COLOR_GRADE == 0
    return color;
#elif COLOR_GRADE == 1
    return mix(color, gradeNaturalColor(color), COLOR_GRADE_STRENGTH);
#else
    float luminance = luma(color);
    float shadow = 1.0 - smoothstep(0.02, 0.40, luminance);
    float highlight = smoothstep(0.25, 0.85, luminance);
    vec3 balance = mix(vec3(1.0), vec3(0.88, 1.015, 1.10), shadow);
    balance *= mix(vec3(1.0), vec3(1.08, 1.015, 0.90), highlight);
    vec3 graded = color * balance;
    graded *= luminance / max(luma(graded), EPSILON);
    graded = mix(graded, vec3(luminance), highlight * 0.12);
    return mix(color, graded, COLOR_GRADE_STRENGTH);
#endif
}
