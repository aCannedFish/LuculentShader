// Vertex transform.
#ifndef LIB_VERTEX_TRANSFORM_GLSL
#define LIB_VERTEX_TRANSFORM_GLSL

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

in vec2 mc_midTexCoord;

/*
 * 执行一次完整的 gbuffers 顶点变换。
 *
 * 参数（都来自顶点属性，没有的就是默认值）：
 *   position      模型空间顶点位置，通常来自 vec4(vaPosition + modelOffset, 1.0)
 *   normal        模型空间法线，通常来自 vaNormal
 *   texCoord      已经由 gl_TextureMatrix[0] 变换的贴图坐标
 *   lightmapCoord 已经由 gl_TextureMatrix[1] 变换的光照贴图坐标
 *   color         顶点颜色，通常来自 vaColor
 *   materialId      方块/实体 ID，legacyEntity
 *
 * 副作用：写入所有 SIMPLE_VARYING 以及 gl_Position。
 */
void transformGBuffersVertex(vec3 position, vec3 normal, vec2 texCoord,
                             vec2 lightmapCoord, vec4 color, vec2 materialId) {
    // --- 1. 世界空间 -> 视图空间 ---
    // 模型空间因几何类型而异：地形属于区块，实体属于模型。
    // modelViewMatrix 包含当前绘制对象的变换；仅用全局
    // gbufferModelView 会漏掉区块平移，把大量顶点挤在原点附近。
    vec4 viewPos = modelViewMatrix * vec4(position, 1.0);
    vViewPos = viewPos.xyz;
#ifndef IS_IRIS
    if (entityId == LIGHTNING_ENTITY_ID) {
        recordLightningGeometry((gbufferModelViewInverse * viewPos).xyz);
    }
#endif

    // --- 2. 视图空间 -> 裁剪空间 ---
    // 透视投影矩阵会把远处的顶点压向屏幕中心（近大远小），
    // 同时把 w 分量设成"到摄像机的距离"，为后面的透视除法做准备。
    gl_Position = postJitterPosition(projectionMatrix * viewPos);

    // --- 3. 法线 ---
    // 只取左上角 3x3 做旋转，不平移。
    // 法线要用当前对象的逆转置矩阵，不能只用全局摄像机矩阵。
    // vaNormal 有时是全零（例如粒子），safeNormalize 会退回 (0,0,1)，
    // 避免 normalize(0) 产生 NaN 把整块画面染黑。
    vNormalView = safeNormalize(normalMatrix * normal, vec3(0.0, 0.0, 1.0));

    // --- 4. 阴影坐标 ---
    // 视图空间先转回世界空间，再用太阳的矩阵变换到阴影裁剪空间。
    // 中间必须经过 gbufferModelViewInverse：shadowModelView 接受的是
    // 世界空间坐标，不是视图空间坐标。漏掉这一步会导致阴影完全错位。
    vec4 shadowClipPos = shadowProjection * shadowModelView * gbufferModelViewInverse * viewPos;

    // 只传线性投影；径向畸变由片元阶段执行，不能先畸变再插值。
    vShadowClipPos = shadowClipPos;

    // --- 5. 原样透传的属性 ---
    vTexCoord      = texCoord;
    bool terrainStage = isTerrainStage();
    vPbrTile = terrainStage ? vec4(mc_midTexCoord, abs(texCoord - mc_midTexCoord)) : vec4(0.0);
    vLightmapCoord = lightmapCoord;
    vEntityId      = materialId;

    // --- 6. 顶点颜色（有一个大坑） ---
    // 某些地形渲染路径的顶点 alpha 可能接近 0。
    //
    // 如果原样传到片元着色器，就会变成：
    //     albedo = texture(gtexture, uv) * vColor;   // albedo.a = 0
    //     if (albedo.a < alphaTestRef) discard;       // 0 < 0.1，全丢
    // 这种情况下，alpha 测试会丢弃地形像素。
    //
    // 处理办法和主流光影包一致：只把"接近 0"的 alpha 归一到 1，
    // 真正的半透明（粒子淡出等，alpha 在 0.1 以上）原样保留。
    vColor = color;
    // Particle alpha is native coverage, including its final fade-out.
    if (vColor.a < 0.1 && !isParticleStage()) {
        vColor.a = 1.0;
    }
}

#endif  // LIB_VERTEX_TRANSFORM_GLSL
