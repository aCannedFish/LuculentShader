// Native vertices use different origins in Sodium terrain and vanilla draws.
#ifndef LIB_VERTEX_INPUT_GLSL
#define LIB_VERTEX_INPUT_GLSL

#include "/lib/uniforms.glsl"
uniform vec3 modelOffset;
#ifdef IS_IRIS
uniform vec3 chunkOffset;
#endif

// Sodium includes per-draw translation in vaPosition but keeps its region origin
// in chunkOffset. Vanilla actors and OptiFine retain the modelOffset contract.
vec3 nativeModelOffset() {
#ifdef IS_IRIS
    return isTerrainStage() ? chunkOffset : modelOffset;
#else
    return modelOffset;
#endif
}

#endif
