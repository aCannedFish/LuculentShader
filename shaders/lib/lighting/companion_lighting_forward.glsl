// Companion lighting for forward.
#ifndef LIB_COMPANION_LIGHTING_GLSL
#define LIB_COMPANION_LIGHTING_GLSL
/* Compact local lighting. Fixed-size C5 is an image-only integer voxel store,
 * C10 holds three source identities, C11 their cached RGB transmission,
 * and C8 low-energy diffuse radiance. Direct RGB contributions remain separate
 * until the material consumer adds their independently shadowed radiance.
 */
#include "/lib/lighting/local_volume.glsl"

#include "/lib/lighting/local_irradiance.glsl"

#include "/lib/lighting/companion_protocol.glsl"

#endif
