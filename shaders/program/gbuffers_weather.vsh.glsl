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

/* 天气顶点阶段。使用加载器提供的雨雪几何与统一视图投影，输出透明绘制所需属性。
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

uniform sampler2D gtexture;
uniform sampler2D gaux2;
uniform sampler2D gaux1;
uniform float rainBiome;
flat SIMPLE_VARYING float vRainDraw;

// Identify the submitted sprite once per vertex. Vanilla rain and snow are
// both 64x256, and resource packs can change both their colours and dimensions.
// Ambiguous identical sprites follow the local precipitation classification.
float nativeRainDraw() {
    ivec2 size = textureSize(gtexture, 0);
    bool rain = all(equal(size, textureSize(gaux2, 0)));
    bool snow = all(equal(size, textureSize(gaux1, 0)));
    for (int i = 0; i < 16 && rain && snow; ++i) {
        vec2 point = fract(vec2(0.37, 0.61) + float(i) * vec2(0.381966, 0.618034));
        ivec2 pixel = min(ivec2(point * vec2(size)), size - 1);
        vec4 value = texelFetch(gtexture, pixel, 0);
        rain = all(equal(value, texelFetch(gaux2, pixel, 0)));
        snow = all(equal(value, texelFetch(gaux1, pixel, 0)));
    }
    return rain ? (snow ? step(0.5, rainBiome) : 1.0) : 0.0;
}

void main() {
    vRainDraw = nativeRainDraw();
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
    // 天气顶点 alpha 包含雨幕的边缘淡出，不能沿用地形的零 alpha 修复。
    vColor = vaColor;
}

