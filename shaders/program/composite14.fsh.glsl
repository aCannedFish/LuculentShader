#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* 垂直泛光过滤，复用已经用完的亮部附件；首个 alpha 继续保留太阳可见度。 */
/* RENDERTARGETS: 3 */
/* HDR 泛光：先逐样本提取亮部再降采样，随后执行可分离过滤。
 * 缓冲只使用左下有效视口，所有读取限制到有效纹素中心，避免采到旧天空/体积场。
 * 阈值和峰值限制先于平均，保留细小光源并抑制极亮像素的闪烁。
 */
#include "/lib/core/bloom_composite12.glsl"

uniform sampler2D colortex4;

void main() {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 uv = gl_FragCoord.xy / bloomSize();
    float visibility = 0.0;
    if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
        visibility = texture(colortex4, vec2(0.5) / size).a;
    }
    fullOut0 = vec4(filterBloom(colortex4, uv, vec2(0.0, 1.0)), visibility);
}

