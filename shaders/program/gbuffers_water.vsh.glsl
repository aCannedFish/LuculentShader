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

/* 水体顶点阶段。仅对水面顶面施加世界坐标波浪位移，保留边界与非水材质。
 * 片元阶段使用同一高度场计算波浪法线。
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

/* 水面光学与波浪工具。共享 Fresnel、八面体法线编码和连续波浪高度场。
 * 三组正弦分量使用绝对世界坐标保持区块接缝连续，正弦差公式直接求差分法线。
 */
#include "/lib/water/surface_data_vertex.glsl"

out float vWaterRestHeight;
void main() {
    float alias = mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    // 复制一份位置，因为我们要在它上面做位移。
    // vec4(vaPosition + nativeModelOffset(), 1.0) 是只读的顶点属性，先复制再修改。
    vec3 displacedPosition = vec4(vaPosition + nativeModelOffset(), 1.0).xyz;

    // 转成绝对世界坐标再取相位，波浪才不会跟着玩家跑（见 lib/water.glsl 的说明）。
    vec3 playerPos = (gbufferModelViewInverse * modelViewMatrix * vec4(vaPosition + nativeModelOffset(), 1.0)).xyz;
    vWaterRestHeight = playerPos.y;
#if ENABLE_WATER_WAVES == 1
    vec2 worldXZ = (playerPos + cameraPosition).xz;

    // 只在竖直方向上做位移。水平方向不动，避免水体出现"缝"。
    float localHeight = fract(playerPos.y + cameraPosition.y + 0.0001);
    if (abs(legacyEntity.x - WATER_BLOCK_ID) < 0.5 && (vaNormal.y > 0.9 || localHeight > 0.01)) {
        float pixelAngle = 2.0 * abs(gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0);
        float resolved = isEyeInWater == 0 ? waterResolvedWave(length(playerPos), playerPos.y, pixelAngle) : 1.0;
        displacedPosition.y += getWaterWaveHeight(worldXZ, frameTimeCounter) * resolved;
    }
#endif

    // 位移完之后，走标准的顶点变换流程。
    // 法线不在顶点阶段修改 —— 逐顶点的法线插值会太平滑，
    // 波浪的细节会糊掉，所以法线留到片元着色器里按像素计算。
    transformGBuffersVertex(
        displacedPosition, vaNormal,
        vaUV0,
        ((vec2(vaUV2) + 8.0) / 256.0),
        vaColor, legacyEntity
    );
}

