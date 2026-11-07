// Iris 的原生闪电几何，沿用引擎折线与分叉，不重新生成电弧位置。
#define SIMPLE_VARYING out
in vec3 vaPosition;
in vec4 vaColor;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
#include "/lib/core/vertex_input.glsl"
SIMPLE_VARYING vec4 vLightningColor;

void main() {
    vec4 view = modelViewMatrix * vec4(vaPosition + nativeModelOffset(), 1.0);
    if (vaColor.g >= min(vaColor.r, vaColor.b) * 0.75) {
        recordLightningGeometry((gbufferModelViewInverse * view).xyz);
    }
    gl_Position = postJitterPosition(projectionMatrix * view);
    vLightningColor = vaColor;
}
