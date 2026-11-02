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

ivec2 waterFaceAddress(int record, int word) {
    ivec2 size = imageSize(colorimg5);
    int end = (size.y - 1) * size.x;
    int address = end - waterFaceCount * waterFaceWords + record * waterFaceWords + word;
    return ivec2(address % size.x, address / size.x);
}

vec2 waterFaceAxes(vec3 v, int axis) {
    return axis == 0 ? v.zy : (axis == 1 ? v.xz : v.xy);
}
