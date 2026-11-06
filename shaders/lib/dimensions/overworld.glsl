// Overworld environment: fog colour, ambient light and background.
vec3 dimensionFogColor() {
    return toLinearSpace(fogColor);
}

vec3 dimensionAmbient(vec3 normalWorld) {
    return vec3(0.0);
}

vec3 dimensionBackground(vec3 direction) {
    return dimensionFogColor() * mix(0.85, 1.05, direction.y * 0.5 + 0.5);
}
