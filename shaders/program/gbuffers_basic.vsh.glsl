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
in vec3 mc_Entity;

/*
================================================================================
 gbuffers_basic.vsh —— 最基础的几何体顶点着色器
================================================================================
 什么时候会用到这个程序？
   - 生物拴绳、区块边界框、某些调试线框等"只有位置和颜色、没有贴图"的几何体
   - 也是所有其它 gbuffers 程序的兜底：如果某个程序类型没有对应的文件，
     OptiFine 会退回使用 gbuffers_basic

 由于它是最简的，代码几乎就是把顶点变换 + 透传属性走一遍。
 把它当作所有 gbuffers 程序的模板来读最合适：
 结构是「读取顶点属性 -> 变换 -> 写入 SIMPLE_VARYING」。
================================================================================
*/

// 引入公共顶点变换。它内部会包含 settings / uniforms / space / varyings。
/*
================================================================================
 lib/vertex_transform.glsl —— gbuffers 顶点变换（顶点着色器专用）
================================================================================
 所有 gbuffers_* 程序的顶点着色器做的事情几乎一样：
   1. 把顶点从"世界空间"变换到"视图空间"，再投影到屏幕；
   2. 顺便把同一批数据用阴影摄像机的矩阵再变换一次，得到阴影采样坐标；
   3. 把法线、贴图坐标、光照贴图坐标、颜色等原样传给片元着色器。

 把这段逻辑抽出来，好处是：
   * 每个 gbuffers_*.vsh 只剩下不到 30 行，一眼能看完；
   * 想改坐标约定（例如加水面波浪、加模型动画），
     在这里改一次，所有程序同时生效，不会出现"某个程序忘了改"的 bug。

 【只应被 .vsh 引用】—— 它写入了 gl_Position，片元着色器里不存在这个变量。
================================================================================
*/
#include "/lib/surface/vertex_transform.glsl"

/* ---------------------------------------------------------------------------
 * 顶点属性
 *   GLSL 120 兼容配置使用 gl_* 内置属性。legacyEntity 是额外属性。
 * ------------------------------------------------------------------------ */

// vec4(vaPosition + nativeModelOffset(), 1.0) 是模型空间位置；地形属于区块，实体属于模型。
// vec4(vaUV0, 0.0, 1.0) 是图集坐标，vec4(vec2(vaUV2), 0.0, 1.0) 是光照贴图坐标。
// 两套坐标都先经过对应的 gl_TextureMatrix 再交给片元着色器。

// 方块或实体的 ID。x = ID，y = 渲染类型。
// basic 程序里基本用不到，但声明出来可以原样传给片元着色器备用。

void main() {
    float alias = mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    // 一行搞定：变换坐标 + 填充所有 SIMPLE_VARYING。
    // 具体每一步在 lib/vertex_transform.glsl 里有逐行注释。
    transformGBuffersVertex(
        vec4(vaPosition + nativeModelOffset(), 1.0).xyz, vaNormal,
        vaUV0,
        ((vec2(vaUV2) + 8.0) / 256.0),
        vaColor, legacyEntity
    );
}

