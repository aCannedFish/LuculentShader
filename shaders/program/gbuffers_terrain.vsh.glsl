#define SIMPLE_VARYING out
SIMPLE_VARYING float vChunkFade;

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
 gbuffers_terrain.vsh —— 地形顶点着色器（全包最核心的程序）
================================================================================
 地形（石头、泥土、木头、树叶、草……）是画面里像素最多的东西，
 这个程序决定了整个光影的观感。

 ------------------------------------------------------------------------------
 数据是怎么流过来的？
 ------------------------------------------------------------------------------
   Minecraft 把每个方块面拆成两个三角形，每个三角形三个顶点。
   每个顶点带着：位置、法线、贴图坐标、光照贴图坐标、颜色、方块 ID。
   OptiFine 的兼容配置通过 vec4(vaPosition + nativeModelOffset(), 1.0)、vaColor 等内置属性提供数据：
     位置 -> 投影到屏幕（决定这个顶点画在屏幕哪里）
     其它 -> 原样传给片元着色器（决定这个像素是什么颜色）

 ------------------------------------------------------------------------------
 为什么顶点着色器这么短？
 ------------------------------------------------------------------------------
   因为真正的"每像素"工作全部在片元着色器里。顶点着色器每帧只跑
   几百万次（顶点数），片元着色器要跑几亿次（像素数），
   所以计算量的分配天然是"顶点轻、片元重"。
   顶点着色器的职责就是：把数据搬到屏幕空间 + 插值传递。

 ------------------------------------------------------------------------------
 关于 gbuffers_terrain_a
 ------------------------------------------------------------------------------
   带 _a 后缀的程序（gbuffers_terrain_a）是【半透明】地形（水下的玻璃、
   半透明树叶等）。OptiFine 会自动复用同一个 gbuffers_terrain.vsh/.fsh，
   只是把渲染状态改成 alpha 混合，并把 alphaTestRef 置 0。
   所以这里不需要写两套代码。
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

/*
 * 植被顶点风摆。地形和阴影共用世界坐标、时间、分类与位移函数。
 * 叶片采用连续空间场以保持相邻方块接缝；草/花/作物以根部为固定支点。
 * 两格植物的上下部分使用同一根部、相位和高度曲线。
 */
#include "/lib/core/foliage_wind.glsl"

// legacyEntity 是可选的自定义属性；基础顶点数据使用 gl_* 内置属性。

in vec3 at_midBlock;

// Save the native sky-light column while the game's lightmap is bound.
// The final C5 row is outside both voxel volumes. Only one vertex per frame
// copies the 16 entries, shared by every secondary water hit.
uniform sampler2D lightmap;
layout(r32ui, binding=5) uniform uimage2D colorimg5;
void captureWaterLightmap() {
    if ((gl_VertexID & 255) != 0) return;
    int row = imageSize(colorimg5).y - 1;
    ivec2 lockPixel = ivec2(16, row);
    uint stamp = uint(frameCounter) + 1u;
    if (imageLoad(colorimg5, lockPixel).r == stamp) return;
    if (imageAtomicExchange(colorimg5, lockPixel, stamp) == stamp) return;
    for (int i = 0; i < 16; ++i) {
        uint value = packUnorm4x8(texelFetch(lightmap, ivec2(0, i), 0));
        imageStore(colorimg5, ivec2(i, row), uvec4(value));
    }
}

void main() {
    vChunkFade = 1.0;
#if ENABLE_CHUNK_TRANSITION == 1 && defined(IRIS_FEATURE_FADE_VARIABLE)
    // Iris 自动声明 mc_chunkFade；负值表示此绘制路径没有区块渐入数据。
    if (mc_chunkFade >= 0.0) {
        vChunkFade = smoothstep(0.0, 1.0, mc_chunkFade);
    }
#endif
    captureWaterLightmap();
    float alias = mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    vec3 position = vec4(vaPosition + nativeModelOffset(), 1.0).xyz;
    vec3 normal = vaNormal;
    if (hasFoliageWind(legacyEntity.x)) {
        vec3 viewPosition = (modelViewMatrix * vec4(vaPosition + nativeModelOffset(), 1.0)).xyz;
        vec3 worldPosition = viewToAbsoluteWorld(viewPosition);
        vec3 blockCenter = worldPosition + at_midBlock / 64.0;
        vec3 root = foliageRoot(blockCenter, legacyEntity.x);
        // 区块模型坐标的轴与世界轴一致；同一偏移用于主视图和阴影。
        vec3 displacement = foliageWindOffset(worldPosition, root, legacyEntity.x);
        position += displacement;
        normal = foliageWindNormal(worldPosition, root, legacyEntity.x, vaNormal, displacement);
    }
    /* 一次调用完成四件事（实现见 lib/vertex_transform.glsl）：
     *
     *   1. viewPos      = modelViewMatrix * vec4(vaPosition + nativeModelOffset(), 1.0)
     *                     模型空间 -> 视图空间（包含区块偏移）
     *   2. gl_Position  = projectionMatrix * viewPos
     *                     视图空间 -> 裁剪空间，交给 GPU 做透视除法与光栅化
     *   3. vNormalView  = 用模型视图矩阵旋转法线
     *   4. vShadowClipPos = shadowProjection * shadowModelView *
     *                       gbufferModelViewInverse * viewPos
     *                     把同一个顶点再从太阳的视角投影一次
     *
     * 注意第 4 步里 gbufferModelViewInverse 不能省：
     * shadowModelView 接受的是世界空间坐标，而我们手上是视图空间坐标。
     */
    transformGBuffersVertex(
        position, normal,
        vaUV0,
        ((vec2(vaUV2) + 8.0) / 256.0),
        vaColor, legacyEntity
    );
}

