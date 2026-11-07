// HDR optics, adaptive exposure, film grading and display conversion.
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 sceneOut;
in vec2 vScreenUv;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/core/space_forward.glsl"
#include "/lib/core/tonemap.glsl"
#include "/lib/post/bloom.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
#include "/lib/core/lens_optics_final.glsl"

void main() {
    vec2 uv = vScreenUv;
    vec3 color = sampleChromaticScene(colortex0, uv);
#if ENABLE_BLOOM == 1
    color += textureLod(colortex3, bloomUv(uv), 0.0).rgb * BLOOM_STRENGTH;
#endif
    color += lensFlare(uv, texelFetch(colortex3, ivec2(0), 0).a);
#if ENABLE_AUTO_EXPOSURE == 1
    color *= texelFetch(colortex13, ivec2(1, 0), 0).x;
#else
    vec3 sunWorld = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float night = 1.0 - smoothstep(-0.16, 0.12, sunWorld.y);
#if SIMPLE_DIMENSION != 0
    night = 0.0;
#endif
    float shadowLift = 0.04 / (0.04 + max(luma(color), 0.0));
    color *= mix(1.0, NIGHT_EXPOSURE, night * shadowLift);
#endif
    color = postWhiteBalance(color);
    color = applyTonemap(color);
    vec2 centered = (uv - 0.5) * vec2(aspectRatio, 1.0);
    color *= max(1.0 - VIGNETTE * dot(centered, centered) * 2.0, 0.0);
    sceneOut = vec4(toDisplaySpace(color), 1.0);
}
