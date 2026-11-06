// End environment: fog colour, ambient light and background.
vec3 dimensionFogColor() {
    return mix(vec3(0.022, 0.016, 0.039), vec3(0.021, 0.020, 0.047), END_ATMOSPHERE * 0.60);
}

vec3 dimensionAmbient(vec3 normalWorld) {
    return mix(vec3(0.46, 0.38, 0.62), vec3(0.75, 0.80, 1.0),
               normalWorld.y * 0.5 + 0.5) * END_AMBIENT
         + vec3(0.010, 0.020, 0.035) * END_ATMOSPHERE * max(normalWorld.y, 0.0);
}

vec3 dimensionBackground(vec3 direction) {
    // Direction-only fields keep the void stable under camera translation and
    // avoid a longitude seam, polar singularity or a second apparent sun.
    float band = sin(direction.x * 4.0 + direction.y * 3.0)
               * sin(direction.z * 5.0 - direction.y * 2.0);
    float wisps = pow(clamp(band * 0.5 + 0.5, 0.0, 1.0), 4.0);
    vec3 p = direction * 540.0;
    float seed = hash13(floor(p));
    float star = (1.0 - smoothstep(0.08, 0.32, length(fract(p) - 0.5)))
               * step(0.9985, seed);
    vec3 base = dimensionFogColor() * (0.65 + wisps * 0.65)
              + vec3(0.30, 0.36, 0.50) * star * 0.35 * (1.0 - smoothstep(0.0, 0.1, END_ATMOSPHERE));
    float phase = frameTimeCounter * TAU / 3600.0;
    vec3 drift = vec3(sin(phase * 2.0), 0.0, cos(phase * 2.0)) * 0.20;
    float warp = atmosphereNoise3(direction * 3.0 + drift);
    float plane = dot(direction, normalize(vec3(0.35, 0.82, 0.24))) + (warp - 0.5) * 0.35;
    float nebula = exp(-plane * plane * 32.0);
    float detail = atmosphereNoise3(direction * 11.0 + drift);
    vec3 palette = mix(vec3(0.065, 0.018, 0.090), vec3(0.018, 0.075, 0.10), detail);
    return base + palette * nebula * (0.20 + detail * detail) * END_ATMOSPHERE;
}
