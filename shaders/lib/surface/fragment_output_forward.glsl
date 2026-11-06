// Fragment output for forward.
#ifndef LIB_FRAGMENT_OUTPUT_GLSL
#define LIB_FRAGMENT_OUTPUT_GLSL

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

/*
 * color_space.glsl —— 游戏颜色输入的显示空间转换。
 *
 * 贴图、顶点色、天空色和雾色由游戏按显示颜色提供。它们参与光照、
 * 雾和泛光之前，先转到线性空间；final.fsh 最后再编码回显示空间。
 * 这里使用与 lib/tonemap.glsl 相配的 gamma 2.2 近似。
 */
#include "/lib/core/color_space.glsl"

/* 表面光照。分别计算日月直射、天空环境光与局部方块光；AO 作用于间接项。
 * 配套数据就绪时接入独立点光阴影和体素 GI，其他情况使用原版光照场。
 */
#include "/lib/lighting/lighting_forward.glsl"

/* 日月阴影入口。返回 RGB 光传递：不透明遮挡为 0，彩色玻璃按透射色染色，
 * 发光方块以自身颜色按遮挡距离照亮它投下的阴影。
 */
#include "/lib/lighting/shadow.glsl"

/*
================================================================================
 lib/varyings.glsl —— 顶点着色器 -> 片元着色器 的数据传递
================================================================================
 SIMPLE_VARYING 是顶点着色器的输出、片元着色器的输入，GPU 会在三角形内部做插值。

 顶点和片元两侧的 SIMPLE_VARYING 声明【必须完全一致】（名称、类型、顺序无所谓但
 名称必须相同），否则链接会失败或数据错乱。为了避免两边写不一样，
 本项目把 SIMPLE_VARYING 集中在这里，两侧都 #include 这一份。

 插值的含义：如果一个三角形三个顶点分别是红、绿、蓝，中间像素拿到的
 是三者按距离加权的结果 —— 这就是为什么渐变能自动生效。
================================================================================
*/
#include "/lib/surface/varyings.glsl"

// 方块/物品的贴图图集。天气、粒子等程序也会绑定这张图集。
uniform sampler2D gtexture;

/* ---------------------------------------------------------------------------
 * 实体叠加色
 *   实体受伤会闪红。游戏不通过改变顶点颜色实现，而是提供 entityColor，
 *   它的 a 分量表示叠加强度。
 * ------------------------------------------------------------------------ */
vec4 applyEntityColor(vec4 color) {
    color.rgb = mix(color.rgb, toLinearSpace(entityColor.rgb), entityColor.a);
    return color;
}

/* ---------------------------------------------------------------------------
 * 写出 G-Buffer
 *
 * 参数：
 *   color       已经算完光照（+雾）的线性空间颜色，可以大于 1
 *   normalView  视图空间法线
 *   lightmapCoord 光照贴图坐标（x = 方块光，y = 天空光）
 *   shadow      阴影系数
 *   material    材质标记，用 lib/common.glsl 里的 MAT_* 常量
 *   alpha       输出到 colortex0 的透明度
 * ------------------------------------------------------------------------ */
void writeGBuffers(vec3 color, vec3 normalView, vec2 lightmapCoord,
                   float shadow, float material, float alpha) {
    vec2 lm = prepareLightmapCoord(lightmapCoord);

    // 目标 0：场景颜色。这是后处理真正会去读的那张图。
    fullOut0 = vec4(color, alpha);

    // 目标 1：八面体法线与几何标记；RGBA8 存储保留有限的角度精度。
    fullOut1 = vec4(encodeNormal(normalView), lm.y, material);

    // 目标 2：光照信息。后处理和调试视图都要用。
    fullOut2 = vec4(lm.x, lm.y, shadow, 0.0);
    // 无材质数据的几何清除后方表面遗留的PBR参数。
    fullOut3 = vec4(0.0);
    // 手部程序不映射该附件，也不生成写入，保证原生场景背景完整保留。
#ifndef FIRST_PERSON_HAND
    fullOut4 = vec4(color, 1.0);
#endif
}

// 彩色日光传递在缓冲中只保留平均可见度。
void writeGBuffers(vec3 color, vec3 normalView, vec2 lightmapCoord,
                   vec3 shadow, float material, float alpha) {
    writeGBuffers(color, normalView, lightmapCoord, dot(shadow, vec3(1.0 / 3.0)), material, alpha);
}

#endif  // LIB_FRAGMENT_OUTPUT_GLSL
