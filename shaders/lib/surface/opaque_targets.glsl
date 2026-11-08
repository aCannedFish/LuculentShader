// Opaque draws retain indirect radiance until deferred surface composition.
// C4 is reused by the later volume and bloom stages; hands never attach it.
#ifndef LIB_OPAQUE_TARGETS_GLSL
#define LIB_OPAQUE_TARGETS_GLSL
#include "/settings.glsl"

#if SSAO_QUALITY > 0
#define LUCULENT_CAPTURE_INDIRECT (1)
layout(location=5) out vec4 indirectOut;
vec3 surfaceIndirectRadiance = vec3(0.0);
/* RENDERTARGETS: 0,1,2,14,15,4 */
#else
/* RENDERTARGETS: 0,1,2,14,15 */
#endif
#endif
