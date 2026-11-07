// TAA resolves HDR and publishes next-frame history plus camera state.
/* RENDERTARGETS: 0,13 */
layout(location=0) out vec4 sceneOut;
layout(location=1) out vec4 historyOut;
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/core/common.glsl"
#include "/lib/water/surface_data_history.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex9;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex2;
#include "/lib/post/history.glsl"
#include "/lib/post/temporal.glsl"
#include "/lib/post/exposure.glsl"

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    bool valid = postHistoryValid(colortex13);
    float depth;
    vec3 color = postTemporalResolve(pixel, uv, valid, depth);
    sceneOut = vec4(color, 1.0);
    historyOut = vec4(color, depth);
    if (pixel.y == 0) {
        if (pixel.x == 0) {
            vec2 medium = isEyeInWater == 1 ? estimateWaterMedium(colortex9) : vec2(0.0);
            historyOut = vec4(medium, float(frameCounter), isEyeInWater == 1 ? 4183.0 : 0.0);
        } else if (pixel.x == 1) {
            historyOut = postUpdateExposureFocus(valid);
        } else if (pixel.x == 2) {
            historyOut = vec4(float(frameCounter), viewWidth, viewHeight, POST_HISTORY_SIGNATURE);
        } else if (pixel.x == 3) {
            historyOut = vec4(postRawProjection()[0][0], postRawProjection()[1][1],
                float(isEyeInWater), valid ? 1.0 : 0.0);
        }
    }
}
