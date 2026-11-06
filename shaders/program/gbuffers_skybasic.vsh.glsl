#define SIMPLE_VARYING out

in vec3 vaPosition;
in vec4 vaColor;
in vec3 vaNormal;
in vec2 vaUV0;
in ivec2 vaUV2;
#include "/lib/core/vertex_input.glsl"
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;

/*
================================================================================
 gbuffers_skybasic.vsh —— 原版天空（渐变穹顶）顶点着色器
================================================================================
 这是唯一一个不共用 lib/vertex_transform.glsl 的 gbuffers 程序，原因是：

   1. 天空穹顶的顶点坐标是"反投影"出来的（永远贴在远平面上），
      MC 直接给出了最终位置，用固定管线的组合矩阵变换即可。
   2. 天空不需要阴影坐标 —— 它是无穷远的，算阴影毫无意义，
      而且它在屏幕上占据大片区域，省下这几步能实打实提升帧率。

 这里用 (projectionMatrix * modelViewMatrix)（固定管线内置的"投影 × 模型视图"矩阵），
 它等于 gbufferProjection * gbufferModelView，效果等价但少一次矩阵乘法。
================================================================================
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

void main() {
    // 天空穹顶直接投影到屏幕。
    // 天空没有"阴影"概念，所以 vShadowClipPos 留空（写 0），
    // 片元着色器也不会去读它。
    gl_Position = (projectionMatrix * modelViewMatrix) * vec4(vaPosition + nativeModelOffset(), 1.0);

    // 原版天空的颜色是"逐顶点渐变"的：天顶一种颜色、地平线一种颜色，
    // 中间靠插值过渡。顶点颜色由 vaColor 提供。
    vColor = vaColor;

    // 天空不参与光照，但为了其它 SIMPLE_VARYING 有确定值，还是写上安全的默认值。
    vNormalView    = vec3(0.0, 0.0, 1.0);
    vViewPos       = vec3(0.0, 0.0, -1.0);
    vShadowClipPos = vec4(0.0);
    vTexCoord      = vec2(0.0);
    vLightmapCoord = vec2(1.0);      // 天空视作"全亮"
    vEntityId      = vec2(0.0);
}

