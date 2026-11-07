// Vertical filtering reuses scene attachments after all water queries finish.
/* RENDERTARGETS: 6,4 */
layout(location=0) out vec4 baseOut;
layout(location=1) out vec4 pyramidOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex14;
uniform sampler2D colortex7;

void main() {
    vec2 pixel = gl_FragCoord.xy;
    float visibility = texelFetch(colortex14, ivec2(0), 0).a;
    vec3 base = postBloomFilter(colortex14, pixel, postBloomRect(0), vec2(0.0, 1.0));
    int level = postBloomLevel(pixel);
    vec3 pyramid = level > 0
        ? postBloomFilter(colortex7, pixel, postBloomRect(level), vec2(0.0, 1.0)) : vec3(0.0);
    baseOut = vec4(base, all(lessThan(pixel, vec2(1.0))) ? visibility : 0.0);
    pyramidOut = vec4(pyramid, 0.0);
}
