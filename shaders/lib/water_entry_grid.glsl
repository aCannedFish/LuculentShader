/* During underwater volume generation C4 holds a world-aligned patch of the
 * interface. Texels carry the refracted solar direction (XZ), visible solar
 * fraction and interface height relative to the camera. The first texel is
 * reserved for the existing medium history. The patch moves in whole texels.
 */
float entryGridSpacing(vec2 size) {
    return clamp(48.0 / max(min(size.x, size.y), 1.0), 0.12, 0.33);
}

vec2 entryGridOrigin(vec2 size, float spacing) {
    return floor(cameraPosition.xz / spacing) - floor(size * 0.5);
}
