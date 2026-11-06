#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* 场景合成后的泛光亮部预过滤；首个 alpha 纹素保存每帧一次的太阳可见度。 */
/* RENDERTARGETS: 3 */
/* HDR 泛光：先逐样本提取亮部再降采样，随后执行可分离过滤。
 * 缓冲只使用左下有效视口，所有读取限制到有效纹素中心，避免采到旧天空/体积场。
 * 阈值和峰值限制先于平均，保留细小光源并抑制极亮像素的闪烁。
 */
#include "/lib/core/bloom_composite12.glsl"

/* 镜头光学近似：太阳的遮挡感知光晕与轻度径向色差。
 * 光晕亮度只在亮部阶段的首个纹素计算一次，再通过附件 alpha 传递。
 */
#include "/lib/core/lens_optics_composite12.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

void main() {
    vec2 uv = gl_FragCoord.xy / bloomSize();
    float visibility = 0.0;
    if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
        visibility = lensSunVisibility(colortex0, depthtex0);
    }
    vec3 bloom = prefilterBloom(colortex0, uv);
    fullOut0 = vec4(bloom, visibility);
}

