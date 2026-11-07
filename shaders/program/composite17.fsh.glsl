// Horizontal Gaussian filtering, with independent bounds for each level.
/* RENDERTARGETS: 14,7 */
layout(location=0) out vec4 baseOut;
layout(location=1) out vec4 pyramidOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex3;
uniform sampler2D colortex4;

void main() {
    vec2 pixel = gl_FragCoord.xy;
    float visibility = texelFetch(colortex3, ivec2(0), 0).a;
    vec3 base = postBloomFilter(colortex3, pixel, postBloomRect(0), vec2(1.0, 0.0));
    int level = postBloomLevel(pixel);
    vec3 pyramid = level > 0
        ? postBloomFilter(colortex4, pixel, postBloomRect(level), vec2(1.0, 0.0)) : vec3(0.0);
    baseOut = vec4(base, all(lessThan(pixel, vec2(1.0))) ? visibility : 0.0);
    pyramidOut = vec4(pyramid, 0.0);
}
