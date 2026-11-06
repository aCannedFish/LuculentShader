#ifndef LUCULENT_WATER_INTERFACE
#define LUCULENT_WATER_INTERFACE
// Unpolarised dielectric Fresnel. eta is incident IOR / transmitted IOR.
// This shared interface law handles air-to-water and the underwater critical angle.
float waterDielectricFresnel(float cosine, float eta) {
    float c = clamp(cosine, 0.0, 1.0);
    float discriminant = 1.0 - eta * eta * (1.0 - c * c);
    if (discriminant <= 0.0) {
        return 1.0;
    }
    float transmitted = sqrt(discriminant);
    float parallel = (eta * c - transmitted) / max(eta * c + transmitted, EPSILON);
    float perpendicular = (c - eta * transmitted) / max(c + eta * transmitted, EPSILON);
    return clamp((parallel * parallel + perpendicular * perpendicular) * 0.5, 0.0, 1.0);
}

// Limit only the coherent reflected image. The physical normal remains
// available to the transmission and direct-light BRDF.
vec3 waterBoundImageNormal(vec3 base, vec3 perturbation) {
    vec3 tilt = perturbation - base * dot(perturbation, base);
    float limit = 1.5 * abs(gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0);
    tilt *= limit / sqrt(limit * limit + dot(tilt, tilt));
    return normalize(base + tilt);
}

#endif
