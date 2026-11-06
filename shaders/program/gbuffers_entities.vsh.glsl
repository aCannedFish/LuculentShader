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
 gbuffers_entities.vsh —— 实体顶点着色器
================================================================================
 渲染对象：生物、掉落物、矿车、船、盔甲架……
 顶点阶段和地形完全一样 —— 实体也是普通的带贴图几何体。
唯一需要注意的是实体的"骨架动画"（僵尸走路、玩家挥手）已经在
    MC 内部算完了，送进来的是动画之后的位置，我们不需要也不应该再去改。
================================================================================
*/

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

void main() {
    float alias = mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    transformGBuffersVertex(
        vec4(vaPosition + nativeModelOffset(), 1.0).xyz, vaNormal,
        vaUV0,
        ((vec2(vaUV2) + 8.0) / 256.0),
        vaColor, legacyEntity
    );
}

