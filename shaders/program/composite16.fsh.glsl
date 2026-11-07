// Pack three area-filtered lower-resolution bloom levels in C4.
/* RENDERTARGETS: 4 */
layout(location=0) out vec4 pyramidOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex3;

void main() {
    int level = postBloomLevel(gl_FragCoord.xy);
    vec3 color = level > 0 ? postBloomDownsample(colortex3, gl_FragCoord.xy, level) : vec3(0.0);
    pyramidOut = vec4(color, 0.0);
}
