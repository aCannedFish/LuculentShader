// Rain particles.
#ifndef LIB_RAIN_PARTICLES_GLSL
#define LIB_RAIN_PARTICLES_GLSL

vec3 shadeRainParticle(vec3 original, vec3 rawAlbedo, vec2 lightmap,
    float alpha, out vec4 overlay) {
    float weight = rainParticleWeight(rawAlbedo);
    overlay = vec4(0.0);
    if (weight <= 0.0) {
        return original;
    }
    vec3 illumination = surfaceAmbient(lightmap, 1.0)
                      + (getSunLightColor() + getMoonLightColor()) * 0.12;
    float intensity = luma(illumination) * mix(0.6, 1.2, luma(rawAlbedo));
    overlay = rainOverlayMoments(intensity, alpha * weight);
    return mix(original, toLinearSpace(rainDropAlbedo()) * intensity, weight);
}

vec3 shadeRainParticle(vec3 original, vec3 rawAlbedo, vec2 lightmap) {
    vec4 overlay;
    return shadeRainParticle(original, rawAlbedo, lightmap, 0.0, overlay);
}

// Rain impacts fade into distance like the streak layer, retaining their shared
// blue-grey radiance rather than being recoloured by the loading-distance fog.
vec3 applyRainParticleFog(vec3 colour, vec3 rawAlbedo, float distance,
    inout float alpha, inout vec4 overlay) {
    vec3 fogged = applySurfaceFog(colour, distance);
    return fogged;
}
#endif
