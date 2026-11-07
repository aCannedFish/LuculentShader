// Depth of field follows temporal reconstruction and camera shutter integration.
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 sceneOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex13;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
#include "/lib/post/history.glsl"
#include "/lib/post/depth_of_field.glsl"

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    sceneOut = vec4(postDepthOfField(uv), 1.0);
}
