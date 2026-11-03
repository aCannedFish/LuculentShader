/* Near-field native terrain faces. A face is usable only after all four
 * boundary corners were observed on the same opaque, axis-aligned face.
 * Interior vertices veto the record. A valid face says nothing about the
 * other five faces or the volume of its block.
 */
const ivec3 waterFaceSize = ivec3(32, 16, 32);
const int waterFaceCount = 98304;
const int waterFaceWords = 20;

ivec3 waterFaceOrigin() {
    return ivec3(floor(cameraPosition)) - waterFaceSize / 2;
}

bool waterFaceInside(ivec3 cell) {
    return all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, waterFaceSize));
}

int waterFaceRecord(ivec3 cell, int axis, bool negative) {
    int index = cell.x + waterFaceSize.x * (cell.y + waterFaceSize.y * cell.z);
    return index * 6 + 2 * axis + int(negative);
}

// Keep the dense waterbed records near the eye. Farther native faces use
// exact keys in a bounded sparse table; an occupied hash slot alone is never
// evidence of geometry. Coarse occupancy only accelerates empty ray segments.
const ivec3 waterFarSize = ivec3(128, 64, 128);
const ivec3 waterMacroSize = ivec3(32, 16, 32);
const int waterFarSlots = 65536;
const int waterMacroCount = 16384;
const int waterColumnCount = 1088;
const int waterTotalFaces = waterFaceCount + waterFarSlots;
const int waterGlassSlots = 8192;
const uint waterGlassMask = 15u << 24u;
const int waterRecordWords = (waterTotalFaces + waterGlassSlots) * waterFaceWords;
const int waterIndexWords = waterFarSlots + waterGlassSlots;
// Actual transparent triangles and their macro lists occupy a separate region.
// A macro only indexes submitted primitives; its volume never supplies a hit.
const int waterTriangleSlots = 32768;
const int waterTriangleNodes = 131072;
const int waterTriangleWords = waterTriangleSlots * 20 + waterTriangleNodes * 2 + waterMacroCount;

// Separate column masks keep transparent-only queries out of opaque terrain.
// The last row also contains the lightmap (0..15) and the frame stamp (17).
ivec2 waterGlassColumn(int column) {
    return ivec2(32 + column, imageSize(colorimg5).y - 1);
}

ivec3 waterFarOrigin() {
    return ivec3(floor(cameraPosition)) - waterFarSize / 2;
}

bool waterFarInside(ivec3 local) {
    return all(greaterThanEqual(local, ivec3(0))) && all(lessThan(local, waterFarSize));
}

ivec2 waterStorageAddress(int offset) {
    ivec2 size = imageSize(colorimg5);
    int end = (size.y - 1) * size.x;
    int address = end - waterRecordWords - waterIndexWords - waterMacroCount - waterColumnCount - waterTriangleWords + offset;
#if defined(COLOURED_VOLUME_SIZE) && (ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0)
    const int profileWidth = COLOURED_VOLUME_SIZE == 32 ? 512 : COLOURED_VOLUME_SIZE * 8;
#else
    const int profileWidth = 512;
#endif
    // A constant divisor avoids integer division for each recorded vertex
    // attribute. Keep the actual allocation authoritative on other layouts.
    if (size.x == profileWidth) return ivec2(address % profileWidth, address / profileWidth);
    return ivec2(address % size.x, address / size.x);
}

ivec2 waterFaceAddress(int record, int word) {
    return waterStorageAddress(record * waterFaceWords + word);
}

ivec2 waterKeyAddress(int slot) {
    return waterStorageAddress(waterRecordWords + slot);
}

ivec2 waterGlassKeyAddress(int slot) {
    return waterStorageAddress(waterRecordWords + waterFarSlots + slot);
}

ivec2 waterMacroAddress(int index) {
    return waterStorageAddress(waterRecordWords + waterIndexWords + index);
}

// A 32-bit mask covers all two-block height bands in a horizontal column.
ivec2 waterColumnAddress(int index) {
    return waterStorageAddress(waterRecordWords + waterIndexWords + waterMacroCount + index);
}

ivec2 waterTriangleAddress(int index, int word) {
    return waterStorageAddress(waterRecordWords + waterIndexWords + waterMacroCount + waterColumnCount + index * 20 + word);
}

ivec2 waterTriangleLink(int index, int word) {
    return waterTriangleAddress(waterTriangleSlots, index * 2 + word);
}

ivec2 waterTriangleHead(int macro) {
    return waterTriangleLink(waterTriangleNodes, macro);
}

int waterColumnIndex(ivec3 cell, int side) {
    return (side == 16 ? 1024 : 0) + cell.x / side + (128 / side) * (cell.z / side);
}

int waterMacroIndex(ivec3 local) {
    ivec3 macro = local / 4;
    return macro.x + waterMacroSize.x * (macro.y + waterMacroSize.y * macro.z);
}

// Each 4x4x4 macro stores the submitted face directions for its four
// horizontal slices (24 bits), and which 2x2x2 octants have any records.
uint waterMacroBits(ivec3 cell, int axis, bool negative) {
    ivec3 halfCell = (cell & 3) >> 1;
    int octant = halfCell.x + 2 * halfCell.y + 4 * halfCell.z;
    return (1u << uint(6 * (cell.y & 3) + 2 * axis + int(negative))) | (1u << uint(24 + octant));
}

int waterFindFace(ivec3 owner, int axis, bool negative, bool create, bool glass) {
    ivec3 nearCell = owner - waterFaceOrigin();
    if (!glass && waterFaceInside(nearCell)) return waterFaceRecord(nearCell, axis, negative);
    ivec3 cell = owner - waterFarOrigin();
    if (!waterFarInside(cell)) return -1;
    uint key = uint(6 * (cell.x + waterFarSize.x * (cell.y + waterFarSize.y * cell.z))
        + 2 * axis + int(negative) + 1);
    uint hash = (key ^ (key >> 16u)) * 0x7feb352du;
    hash = (hash ^ (hash >> 15u)) * 0x846ca68bu;
    int slots = glass ? waterGlassSlots : waterFarSlots;
    int home = int((hash ^ (hash >> 16u)) & uint(slots - 1));
    for (int probe = 0; probe < 8; ++probe) {
        int slot = (home + probe) & (slots - 1);
        ivec2 address = glass ? waterGlassKeyAddress(slot) : waterKeyAddress(slot);
        uint entry = create ? imageAtomicCompSwap(colorimg5, address, 0u, key) : imageLoad(colorimg5, address).r;
        if (entry == key || (create && entry == 0u)) return (glass ? waterTotalFaces : waterFaceCount) + slot;
        if (!create && entry == 0u) break;
    }
    return -1;
}

int waterFindFace(ivec3 owner, int axis, bool negative, bool create) {
    return waterFindFace(owner, axis, negative, create, false);
}

vec2 waterFaceAxes(vec3 v, int axis) {
    return axis == 0 ? v.zy : (axis == 1 ? v.xz : v.xy);
}
