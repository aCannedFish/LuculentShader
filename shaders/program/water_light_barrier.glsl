// OptiFine issues the image-access barrier for compute programs before
// subsequent raster stages consume the terrain lightmap written this frame.
layout(local_size_x=2) in;
const ivec3 workGroups = ivec3(1, 1, 1);
void main() {
    memoryBarrierImage();
}
