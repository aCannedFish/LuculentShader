// Combine narrow and broad glow with normalized weights.
/* RENDERTARGETS: 3 */
layout(location=0) out vec4 bloomOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex6;
uniform sampler2D colortex4;

void main() {
    vec2 uv = gl_FragCoord.xy / bloomSize();
    float visibility = texelFetch(colortex6, ivec2(0), 0).a;
    bloomOut = vec4(postBloomCombine(colortex6, colortex4, uv),
        all(lessThan(gl_FragCoord.xy, vec2(1.0))) ? visibility : 0.0);
}
