// Resolve short wind ripples in the surface BRDF. The separate mesh-scale
// height field supplies the slope used for the water-column refraction.
vec3 waterSurfaceNormal(vec2 position, float time, float footprint) {
    float t = time * WAVE_SPEED;
    float rain = mix(1.0, 1.45, weatherRainAmount());
    vec2 slope = waterWaveOctave(position, t, 0.35, 3.20, 2.4, 0.78, 0.075,
                                 vec2(0.0), footprint);
    slope += waterWaveOctave(position, t, -0.28, 1.45, 2.1, 0.60, 0.043,
                             vec2(17.3, -41.9), footprint);
    slope += waterWaveOctave(position, t, 0.70, 0.73, 2.0, 0.43, 0.020 * rain,
                             vec2(-63.1, 27.7), footprint);
    slope += waterWaveOctave(position, t, -0.58, 0.36, 1.8, 0.32, 0.008 * rain,
                             vec2(91.4, 55.2), footprint);

    // Add the slopes before normalization. As the footprint grows the short
    // bands fade away, leaving the same long waves that displaced the mesh.
    vec3 longNormal = getWaterWaveNormal(position, time);
    vec2 tilt = longNormal.xz / longNormal.y - slope * WATER_WAVE_STRENGTH;
    return normalize(vec3(tilt.x, 1.0, tilt.y));
}
