// BSL v7.0p1 camera-velocity blur, limited to the reflection attachment.
// Refraction, main-world colour and the viewmodel never enter this filter.
vec3 bslWaterReflectionBlur(vec2 uv, vec3 position) {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 centre = texelFetch(colortex15, pixel, 0).rgb;
#if WATER_REFLECTION_MOTION_BLUR == 0
    return centre;
#else
    if (frameCounter < 2 || length(cameraPosition - previousCameraPosition) > 8.0) return centre;
    float depth = textureLod(depthtex2, uv, 0.0).r;
    vec4 current = vec4(uv * 2.0 - 1.0, min(depth, 0.9999999) * 2.0 - 1.0, 1.0);
    vec4 world = gbufferModelViewInverse * gbufferProjectionInverse * current;
    world /= world.w;
    world.xyz += cameraPosition - previousCameraPosition;
    vec4 previous = gbufferPreviousProjection * gbufferPreviousModelView * world;
    if (previous.w <= 1e-6) return centre;
    vec2 velocity = current.xy - previous.xy / previous.w;
    velocity *= 0.001 / (max(frameTime, 0.0001) * (1.0 + length(velocity)));
    vec2 size = vec2(textureSize(colortex15, 0));
    if (length(velocity * size) < 0.125) return centre;

    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 sum = centre;
    float weight = 1.0;
    for (int sampleIndex = 0; sampleIndex < 9; ++sampleIndex) {
        vec2 tap = clamp(uv + float(sampleIndex - 4) * velocity, 2.0 / size, 1.0 - 2.0 / size);
        ivec2 tapPixel = ivec2(tap * size);
        vec4 water = texelFetch(colortex9, tapPixel, 0);
        if (water.a < 0.5) continue;
        vec3 neighbour = waterSurfacePosition((vec2(tapPixel) + 0.5) / size, water.b);
        if (abs(dot(neighbour - position, up)) > 0.06) continue;
        vec4 value = textureLod(colortex15, tap, 0.0);
        // In BSL comparison mode alpha is one on water and zero elsewhere.
        // Normalize filtered coverage so a shoreline never borrows black.
        if (value.a <= 0.001) continue;
        sum += value.rgb / value.a;
        weight += 1.0;
    }
    return sum / weight;
#endif
}
