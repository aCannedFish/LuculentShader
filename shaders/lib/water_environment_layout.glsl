#ifndef LUCULENT_WATER_ENVIRONMENT_LAYOUT
#define LUCULENT_WATER_ENVIRONMENT_LAYOUT
#if WATER_REFLECTION_STEPS >= 32
const int waterEnvironmentSide = 256;
#else
const int waterEnvironmentSide = 128;
#endif
const int waterEnvironmentPixels = waterEnvironmentSide * waterEnvironmentSide;
const int waterEnvironmentWords = waterEnvironmentPixels * 5 * 2;

ivec2 waterEnvironmentAddress(ivec2 cell, int bank, int word) {
    int index = cell.x + waterEnvironmentSide * cell.y + bank * waterEnvironmentPixels;
    return waterStorageAddress(-waterEnvironmentWords + index * 5 + word);
}

vec2 waterEnvironmentSign(vec2 p) {
    return mix(vec2(-1.0), vec2(1.0), greaterThanEqual(p, vec2(0.0)));
}

vec2 waterEnvironmentUv(vec3 direction) {
    vec3 p = direction / max(dot(abs(direction), vec3(1.0)), 1e-8);
    vec2 oct = p.z >= 0.0 ? p.xy : (1.0 - abs(p.yx)) * waterEnvironmentSign(p.xy);
    return oct * 0.5 + 0.5;
}

vec3 waterEnvironmentDirection(vec2 uv) {
    vec2 oct = uv * 2.0 - 1.0;
    vec3 p = vec3(oct, 1.0 - abs(oct.x) - abs(oct.y));
    if (p.z < 0.0) p.xy = (1.0 - abs(p.yx)) * waterEnvironmentSign(p.xy);
    return normalize(p);
}

#endif
