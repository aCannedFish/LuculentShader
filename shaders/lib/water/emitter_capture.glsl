// Retain actual submitted emitter triangles, including fluid heights and UVs.
// Bins locate candidates; their occupancy never represents a block surface.
void captureWaterEmitterTriangle() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (isEyeInWater != 0 || !isTerrainStage() || abs(gCaster[0] - 1.0) > 0.1) {
        return;
    }
    vec3 halfSize = vec3(waterFarSize) * 0.5;
    vec3 low = min(gNativePosition[0], min(gNativePosition[1], gNativePosition[2])) + halfSize;
    vec3 high = max(gNativePosition[0], max(gNativePosition[1], gNativePosition[2])) + halfSize;
    if (any(lessThan(high, vec3(0.0))) || any(greaterThanEqual(low, vec3(waterFarSize)))) {
        return;
    }
    vec3 area = cross(gNativePosition[1] - gNativePosition[0], gNativePosition[2] - gNativePosition[0]);
    if (dot(area, area) < 1e-16) {
        return;
    }
    int row = imageSize(colorimg5).y - 1;
    uint triangle = imageAtomicAdd(colorimg5, ivec2(30, row), 1u);
    if (triangle >= uint(waterEmitterCapacity)) {
        imageAtomicOr(colorimg5, waterEmitterAddress(0), 1u);
        return;
    }
    vec2 extent = spriteBounds.zw - spriteBounds.xy;
    bool single = all(greaterThan(extent, vec2(0.0))) && any(notEqual(textureSize(gtexture, 0), atlasSize));
    for (int vertex = 0; vertex < 3; ++vertex) {
        for (int axis = 0; axis < 3; ++axis) {
            imageStore(colorimg5, waterEmitterRecord(int(triangle), vertex * 3 + axis),
                uvec4(floatBitsToUint(gNativePosition[vertex][axis])));
        }
        vec2 uv = single ? spriteBounds.xy + gTexCoord[vertex] * extent : gTexCoord[vertex];
        imageStore(colorimg5, waterEmitterRecord(int(triangle), 9 + vertex), uvec4(packUnorm2x16(uv)));
    }
    ivec3 first = clamp(ivec3(floor(low - 0.0001)), ivec3(0), waterFarSize - 1);
    ivec3 last = clamp(ivec3(floor(high + 0.0001)), ivec3(0), waterFarSize - 1);
    for (int z = first.z; z <= last.z; ++z) {
        for (int y = first.y; y <= last.y; ++y) {
            for (int x = first.x; x <= last.x; ++x) {
                uint node = imageAtomicAdd(colorimg5, ivec2(31, row), 1u);
                if (node >= uint(waterEmitterNodes)) {
                    imageAtomicOr(colorimg5, waterEmitterAddress(0), 2u);
                    return;
                }
                uint key = waterEmitterCellKey(ivec3(x, y, z));
                uint previous = imageAtomicExchange(colorimg5, waterEmitterHead(key), node + 1u);
                imageStore(colorimg5, waterEmitterLink(int(node), 0), uvec4(previous));
                imageStore(colorimg5, waterEmitterLink(int(node), 1), uvec4(triangle));
                imageStore(colorimg5, waterEmitterLink(int(node), 2), uvec4(key));
            }
        }
    }
#endif
}
