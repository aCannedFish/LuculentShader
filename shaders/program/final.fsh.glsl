// Final filtering runs in display space and precedes output dithering.
#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/core/space_forward.glsl"
#include "/lib/core/noise.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
#include "/lib/water_screen_images.glsl"
#include "/lib/core/debug.glsl"
#include "/lib/core/fxaa.glsl"
SIMPLE_VARYING vec2 vScreenUv;

void main() {
    vec3 color = filterDisplayEdges(colortex0, vScreenUv);
    color = applyDither(color, vScreenUv);
    color = applyDebugView(color, vScreenUv);
    fullOut0 = vec4(color, 1.0);
}
