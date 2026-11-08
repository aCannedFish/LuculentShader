// Shared geometry/material queries for the two transmission stages.
// Surface/atmosphere composition owns a separate pipeline.
#ifndef LUCULENT_NATIVE_OPTICS
#define LUCULENT_NATIVE_OPTICS
#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
const bool colortex6MipmapEnabled = false;
#include "/lib/atmosphere/clouds_water.glsl"
#include "/lib/core/space_forward.glsl"
#include "/lib/atmosphere/fog_forward.glsl"
#include "/lib/reflections/water_reflection.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex4;
#endif
