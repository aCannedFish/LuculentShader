// Extract highlights before filtering; alpha carries sun visibility once per frame.
/* RENDERTARGETS: 3 */
layout(location=0) out vec4 bloomOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/post/bloom.glsl"
#include "/lib/core/lens_optics_composite12.glsl"
uniform sampler2D colortex0;
uniform sampler2D depthtex0;

void main() {
    vec2 uv = gl_FragCoord.xy / bloomSize();
    float visibility = 0.0;
    if (all(lessThan(gl_FragCoord.xy, vec2(1.0)))) {
        visibility = lensSunVisibility(colortex0, depthtex0);
    }
    bloomOut = vec4(prefilterBloom(colortex0, uv), visibility);
}
