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
 gbuffers_skytextured.vsh —— 带贴图的天空（末地天空、自定义天空）
================================================================================
 与 skybasic 的唯一区别：这类天空用贴图而不是纯色渐变，
 所以需要把变换后的 vec4(vaUV0, 0.0, 1.0) 传给片元着色器。
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
    gl_Position = (projectionMatrix * modelViewMatrix) * vec4(vaPosition + nativeModelOffset(), 1.0);

    vTexCoord      = vaUV0;
    vColor         = vaColor;
    vNormalView    = vec3(0.0, 0.0, 1.0);
    vViewPos       = vec3(0.0, 0.0, -1.0);
    vShadowClipPos = vec4(0.0);
    vLightmapCoord = vec2(1.0);
    vEntityId      = vec2(0.0);
}

