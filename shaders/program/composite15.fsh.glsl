#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
// 相机介质历史更新。
/* 保存下一帧使用的单纹素介质历史；从原生水面附件估计，不接收外部世界数据。 */
/* RENDERTARGETS: 13 */
/* 水面光学与波浪工具。共享 Fresnel、八面体法线编码和连续波浪高度场。
 * 三组正弦分量使用绝对世界坐标保持区块接缝连续，正弦差公式直接求差分法线。
 */
#include "/lib/water/surface_data_history.glsl"

uniform sampler2D colortex9;
uniform sampler2D colortex1;

void main() {
    vec2 medium = isEyeInWater == 1 ? estimateWaterMedium(colortex9) : vec2(0.0);
    fullOut0 = vec4(medium, float(frameCounter), isEyeInWater == 1 ? 4183.0 : 0.0);
}

