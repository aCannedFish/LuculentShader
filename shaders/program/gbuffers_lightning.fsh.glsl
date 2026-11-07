// 只叠加 HDR 电弧颜色，保留已有世界深度、几何数据与雨幕透射率。
/* RENDERTARGETS: 0 */
#define SIMPLE_VARYING in
#include "/lib/uniforms.glsl"
SIMPLE_VARYING vec4 vLightningColor;
layout(location=0) out vec4 lightningOut;

void main() {
    // 此通道也承载末影龙死亡光束；有色光束保持原生颜色。
    bool neutral = vLightningColor.g >= min(vLightningColor.r, vLightningColor.b) * 0.75;
    vec3 color = neutral ? lightningCoreRadiance(vLightningColor.rgb) : vLightningColor.rgb;
    lightningOut = vec4(color, vLightningColor.a);
}
