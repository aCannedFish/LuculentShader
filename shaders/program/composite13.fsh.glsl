// Pair the history writes for OptiFine's frame-start bank reset.
// Lens blur only changes C0; the synchronized C13 remains unblurred HDR.
/* RENDERTARGETS: 0,13 */
layout(location=0) out vec4 sceneOut;
layout(location=1) out vec4 historyOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
#include "/lib/post/history.glsl"
#include "/lib/post/motion_blur.glsl"

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    sceneOut = vec4(postMotionBlur(uv), 1.0);
    historyOut = texelFetch(colortex13, ivec2(gl_FragCoord.xy), 0);
}
