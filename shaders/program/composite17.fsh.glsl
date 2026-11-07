// Display-colour transform precedes antialiasing; keep the existing
// bloom, lens optics, exposure and tone-map arithmetic in this one pass.
/* RENDERTARGETS: 0 */
#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/core/space_forward.glsl"
#include "/lib/core/tonemap.glsl"
#include "/lib/core/bloom_final.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
#include "/lib/core/lens_optics_final.glsl"
SIMPLE_VARYING vec2 vScreenUv;
void main() {
    vec2 screenCoord = vScreenUv;
    vec3 color = sampleChromaticScene(colortex0, screenCoord);
#if ENABLE_BLOOM == 1
    vec3 bloom = texture(colortex3, bloomUv(screenCoord)).rgb;
    color += bloom * BLOOM_STRENGTH;
#endif
    float solarVisibility = texture(colortex3, vec2(0.5) / vec2(viewWidth, viewHeight)).a;
    color += lensFlare(screenCoord, solarVisibility);
    vec3 sunWorld = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float night = 1.0 - smoothstep(-0.16, 0.12, sunWorld.y);
#if SIMPLE_DIMENSION != 0
    night = 0.0;
#endif
    float shadowLift = 0.04 / (0.04 + max(luma(color), 0.0));
    color *= mix(1.0, NIGHT_EXPOSURE, night * shadowLift);
    color = applyTonemap(color);
    vec2 centered = (screenCoord - 0.5) * vec2(aspectRatio, 1.0);
    color *= 1.0 - VIGNETTE * dot(centered, centered) * 2.0;
    color = toDisplaySpace(color);
    fullOut0 = vec4(color, 1.0);
}
