#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;

/* 最终输出。轻度径向色差、泛光与太阳镜头光晕先在线性空间合成，
 * 再应用夜间曝光、色调映射和颜色调整，最后编码到显示空间。
 * 调试视图可替换最终颜色输出。
 */

/* 全局渲染设置。集中定义加载器常量、缓冲格式和可调宏；各程序共享同一组默认值。
 * 游戏内选项由 shaders.properties 分组，用户选择由加载器保存。
 */
#include "/settings.glsl"

/* 加载器输入声明。集中定义相机、时间、天气、光照、深度与视图/阴影矩阵 uniform。
 */
#include "/lib/uniforms.glsl"

/*
================================================================================
 lib/common.glsl —— 通用常量与数学工具
================================================================================
 这里只放"纯函数"：不声明 uniform、不声明 SIMPLE_VARYING、不读写纹理。
 因此这个文件可以被顶点着色器和片元着色器同时安全地 include。

 命名约定（整个项目统一遵守）：
   - 变量、函数：lowerCamelCase
   - 宏（#define）：UPPER_SNAKE_CASE
   - 顶点属性：GLSL 120 兼容程序使用 gl_* 内置属性
   - uniform：不加前缀，直接用 OptiFine 提供的名字
   - SIMPLE_VARYING：v 开头
   - 材质/枚举：MAT_ 开头
================================================================================
*/
#include "/lib/core/common.glsl"

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_forward.glsl"

/* HDR 亮度映射与色域约束。保持中间调的色相，控制曝光、饱和度、对比度与显示编码。
 */
#include "/lib/core/tonemap.glsl"

/*
================================================================================
 lib/noise.glsl —— 噪声与抖动
================================================================================
 两个用途：

 1. 抖动（dithering）
    8 位颜色每通道只有 256 级。天空、雾这类大面积平滑渐变，相邻两级之间
    的边界会被眼睛看成一条条同心圆状的色带（banding），非常难看。
    解决办法：给每个像素加上一点点（小于 1 个色阶）的随机偏移，
    让色带边界被打散成噪点 —— 噪点人眼会自动忽略，色带不会。

 2. 噪波纹理（noisetex）
    OptiFine 会生成一张 noiseTextureResolution × noiseTextureResolution
    的随机纹理并绑定到 noisetex，可以自由采样。做雨滴、粒子、随机化
    等效果时非常有用，这里先用它做抖动，也是给后续扩展留的接口。
================================================================================
*/
#include "/lib/core/noise.glsl"

/* HDR 泛光：先逐样本提取亮部再降采样，随后执行可分离过滤。
 * 缓冲只使用左下有效视口，所有读取限制到有效纹素中心，避免采到旧天空/体积场。
 * 阈值和峰值限制先于平均，保留细小光源并抑制极亮像素的闪烁。
 */
#include "/lib/core/bloom_final.glsl"

// 场景颜色（所有 gbuffers 程序的输出，包含半透明物体）
uniform sampler2D colortex0;

// 模糊后的泛光
uniform sampler2D colortex3;

// 下面这几个是 lib/debug.glsl 的调试视图要用的。
// 该文件自己不声明采样器（因为它被不同程序共用，能读到的纹理不一样），
// 所以在这里统一声明。用不到的调试视图会被编译器优化掉。
#include "/lib/water_screen_images.glsl"
uniform sampler2D depthtex0;

/* 调试输出。按 DEBUG_VIEW 显示法线、光照贴图、阴影、深度、泛光或重建视图坐标。
 */
#include "/lib/core/debug.glsl"

/* 镜头光学近似：太阳的遮挡感知光晕与轻度径向色差。
 * 光晕亮度只在亮部阶段的首个纹素计算一次，再通过附件 alpha 传递。
 */
#include "/lib/core/lens_optics_final.glsl"

SIMPLE_VARYING vec2 vScreenUv;

void main() {
    // final 的视口是输出窗口；viewWidth/Height 仍表示内部纹理尺寸。
    vec2 screenCoord = vScreenUv;

    /* -----------------------------------------------------------------------
     * 第一步：取出场景颜色
     * -------------------------------------------------------------------- */
    vec3 color = sampleChromaticScene(colortex0, screenCoord);

    /* -----------------------------------------------------------------------
     * 第二步：叠加泛光
     * 泛光是"额外的光"，所以是加法而不是混合。
     * BLOOM_STRENGTH 控制它有多强；太大会让画面糊成一团。
     * -------------------------------------------------------------------- */
#if ENABLE_BLOOM == 1
    vec3 bloom = texture(colortex3, bloomUv(screenCoord)).rgb;
    color += bloom * BLOOM_STRENGTH;
#endif

    float solarVisibility = texture(colortex3, vec2(0.5) / vec2(viewWidth, viewHeight)).a;
    color += lensFlare(screenCoord, solarVisibility);

    /* -----------------------------------------------------------------------
     * 第三步：色调映射（含曝光、饱和度、对比度）
     * 把可能远超 1.0 的 HDR 颜色压回 [0,1]。
     * 这是"为什么高光不会死白"的原因，详见 lib/tonemap.glsl。
     * -------------------------------------------------------------------- */
    // 夜间只抬升暗部；亮光附近逐渐回到基础曝光，避免整片照明被一起放大。
    vec3 sunWorld = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float night = 1.0 - smoothstep(-0.16, 0.12, sunWorld.y);
#if SIMPLE_DIMENSION != 0
    night = 0.0;
#endif
    // 有理衰减使最终亮度保持单调，较大的用户曝光值也不会形成反向光圈。
    float shadowLift = 0.04 / (0.04 + max(luma(color), 0.0));
    color *= mix(1.0, NIGHT_EXPOSURE, night * shadowLift);
    color = applyTonemap(color);

    /* -----------------------------------------------------------------------
     * 第四步：暗角（vignette）
     * 模拟镜头边缘进光量下降，把注意力集中到画面中心。
     * 这里在"以中心为原点"的坐标上算距离平方，再用它压暗。
     * 乘上 aspectRatio 是为了让暗角在宽屏上保持圆形而不是椭圆。
     *
     * 注意这里没有用 #if 包起来：GLSL 的预处理器只支持整数常量表达式，
     * 写 `#if VIGNETTE > 0.0` 是编译错误。好在 VIGNETTE = 0 时
     * 下面这两行的结果就是原值，等于关闭，代价可以忽略。
     * -------------------------------------------------------------------- */
    vec2 centered = (screenCoord - 0.5) * vec2(aspectRatio, 1.0);
    color *= 1.0 - VIGNETTE * dot(centered, centered) * 2.0;

    /* -----------------------------------------------------------------------
     * 第五步：线性空间 -> 显示空间
     * 把线性光强转换成显示器期望的 sRGB 信号。
     * -------------------------------------------------------------------- */
    color = toDisplaySpace(color);

    /* -----------------------------------------------------------------------
     * 第六步：抖动
     * 打散 8 位色深带来的色带。
     * 必须放在 gamma 编码【之后】，因为色带是在最终的显示值上产生的。
     * -------------------------------------------------------------------- */
    color = applyDither(color, screenCoord);

    /* -----------------------------------------------------------------------
     * 第七步：调试视图
     * 必须在最后一步，因为它要绕过上面所有处理直接显示原始数据。
     * settings.glsl 里把 DEBUG_VIEW 设成非 0 即可启用。
     * -------------------------------------------------------------------- */
    color = applyDebugView(color, screenCoord);

    /* -----------------------------------------------------------------------
     * 输出到屏幕
     * -------------------------------------------------------------------- */
    fullOut0 = vec4(color, 1.0);
}

