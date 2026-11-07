/* The underwater triangle arena is idle above water. Reuse a bounded part
 * for native fluid top heights, captured before terrain rendering. A zero
 * entry means unknown; it never licenses clipping a submerged plant.
 */
#include "/lib/water_storage_layout.glsl"

ivec2 waterPlantAddress(int index) {
    ivec2 size = imageSize(colorimg5);
    int address = (size.y - 1) * size.x - waterTriangleWords + index;
    return ivec2(address % size.x, address / size.x);
}

int waterPlantColumn(vec2 world) {
    ivec2 cell = ivec2(floor(world)) - ivec2(floor(cameraPosition.xz)) + waterPlantSide / 2;
    if (any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, ivec2(waterPlantSide)))) return -1;
    return cell.x + cell.y * waterPlantSide;
}

// Only the named aquatic geometry class is clipped. Land plants and resource
// pack alpha remain untouched. Unknown surfaces retain the native geometry.
bool waterPlantAboveSurface(vec3 world, float material) {
    if (isEyeInWater == 1 || abs(material - 205.0) > 0.5) return false;
#if SIMPLE_DIMENSION == 0
    int row = imageSize(colorimg5).y - 1;
    if (imageLoad(colorimg5, ivec2(25, row)).r != uint(frameCounter) + 1u) return false;
    int index = waterPlantColumn(world.xz);
    if (index >= 0) {
        uint value = imageLoad(colorimg5, waterPlantAddress(index)).r;
        if (value != 0u) return world.y >= uintBitsToFloat(value) - 4096.0 - 0.002;
    }
#endif
    return false;
}
