// Nether environment: fog colour, ambient light and background.
vec3 dimensionFogColor() {
    vec3 biome = max(toLinearSpace(fogColor), vec3(0.018, 0.006, 0.004));
    float low = 1.0 - smoothstep(28.0, 85.0, cameraPosition.y);
    float warmBiome = smoothstep(-0.02, 0.08, biome.r - biome.b);
    return mix(biome, biome * vec3(1.12, 0.92, 0.82) + vec3(0.020, 0.003, 0.001),
               NETHER_ATMOSPHERE * low * mix(0.08, 0.42, warmBiome));
}

vec3 dimensionAmbient(vec3 normalWorld) {
    vec3 biome = dimensionFogColor();
    vec3 tint = mix(vec3(0.82, 0.64, 0.51), biome / max(luma(biome), 0.02), 0.18);
    tint = mix(tint, tint * vec3(1.05, 0.97, 0.92), NETHER_ATMOSPHERE * 0.45);
    return tint * NETHER_AMBIENT * (0.70 + 0.30 * max(-normalWorld.y, 0.0));
}

vec3 dimensionBackground(vec3 direction) {
    return dimensionFogColor() * mix(0.85, 1.05, direction.y * 0.5 + 0.5);
}
