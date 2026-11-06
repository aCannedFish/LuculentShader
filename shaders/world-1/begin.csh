#version 450 core
#define SIMPLE_DIMENSION (-1)
// Iris dispatches shadow compute before its frame-uniform notification.
// Begin compute runs after that notification and before shadow geometry.
#ifdef IS_IRIS
#include "/program/shadow.csh.glsl"
#else
// This loader runs the shared setup in the other frame phase.
layout(local_size_x=2) in;
const ivec3 workGroups = ivec3(0, 0, 0);
void main() {}
#endif
