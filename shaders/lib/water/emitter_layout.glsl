// Sparse unit-cell lists only locate actual submitted triangles. A cell or
// hash collision never acts as a surface. Reuse the above-water arena tail.
#ifndef LUCULENT_EMITTER_LAYOUT
#define LUCULENT_EMITTER_LAYOUT
#include "/lib/water_storage_layout.glsl"
const int waterEmitterCapacity = 8192;
const int waterEmitterNodes = 65536;
const int waterEmitterBuckets = 32768;
const int waterEmitterWords = 2 + waterEmitterCapacity * 12
    + waterEmitterNodes * 3 + waterEmitterBuckets;

ivec2 waterEmitterAddress(int offset) {
    ivec2 size = imageSize(colorimg5);
    int address = (size.y - 1) * size.x - waterTriangleWords + waterPlantCells + offset;
    return ivec2(address % size.x, address / size.x);
}

ivec2 waterEmitterRecord(int triangle, int word) {
    return waterEmitterAddress(2 + triangle * 12 + word);
}

ivec2 waterEmitterLink(int node, int word) {
    return waterEmitterAddress(2 + waterEmitterCapacity * 12 + node * 3 + word);
}

uint waterEmitterCellKey(ivec3 cell) {
    return 1u + uint(cell.x + waterFarSize.x * (cell.y + waterFarSize.y * cell.z));
}

ivec2 waterEmitterHead(uint key) {
    uint hash = (key ^ (key >> 16u)) * 0x7feb352du;
    hash = (hash ^ (hash >> 15u)) * 0x846ca68bu;
    int bucket = int((hash ^ (hash >> 16u)) & uint(waterEmitterBuckets - 1));
    return waterEmitterAddress(2 + waterEmitterCapacity * 12 + waterEmitterNodes * 3 + bucket);
}

ivec2 waterEmitterBucket(int bucket) {
    return waterEmitterAddress(2 + waterEmitterCapacity * 12 + waterEmitterNodes * 3 + bucket);
}
#endif
