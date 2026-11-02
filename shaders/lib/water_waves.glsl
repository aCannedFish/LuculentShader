/* Long gravity waves displace the mesh and steer coherent scene rays.
 * Microstructure and individual rain impacts remain in the surface BRDF.
 * Both height and optical slope evaluate the same world-space components.
 */
const float WAVE_SPEED = 1.0;
const vec3 waterWaveAmplitude = vec3(0.020, 0.010, 0.004);
const vec2 waterWaveA = vec2(0.51, 0.22);
const vec2 waterWaveB = vec2(-0.41, 0.68);
const vec2 waterWaveC = vec2(0.34, -1.08);

vec3 waterWavePhase(vec2 world, float time) {
    return vec3(dot(world, waterWaveA), dot(world, waterWaveB), dot(world, waterWaveC))
        + time * vec3(1.15, -0.92, 1.55);
}

float getWaterWaveHeight(vec2 world, float time) {
    return dot(sin(waterWavePhase(world, time)), waterWaveAmplitude) * WATER_WAVE_STRENGTH;
}

vec3 getWaterWaveNormal(vec2 world, float time) {
    vec3 scale = cos(waterWavePhase(world, time)) * waterWaveAmplitude * WATER_WAVE_STRENGTH;
    vec2 slope = scale.x * waterWaveA + scale.y * waterWaveB + scale.z * waterWaveC;
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}
