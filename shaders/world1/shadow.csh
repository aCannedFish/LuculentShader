#version 450 core
#define SIMPLE_DIMENSION (1)
#ifdef IS_IRIS
// This loader runs the shared setup in the other frame phase.
layout(local_size_x=2) in;
const ivec3 workGroups = ivec3(0, 0, 0);
void main() {}
#else
#include "/program/shadow.csh.glsl"
#endif
