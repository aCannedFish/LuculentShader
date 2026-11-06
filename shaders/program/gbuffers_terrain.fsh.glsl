#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* RENDERTARGETS: 0,1,2,14,15 */

/*
================================================================================
 gbuffers_terrain.fsh —— 地形片元着色器
================================================================================
 这是整个光影包最值得逐行读完的文件。所有其它 gbuffers 程序都是它的简化版。

 计算流程（每一步在下面都有对应代码块）：

    贴图采样 ──> alpha 测试 ──┐
                              ├──> 光照 ──> 雾 ──> 写入 G-Buffer
    光照贴图采样 ─────────────┤
    阴影贴图采样 ─────────────┘

 最终写出的颜色是【线性空间】的 HDR 值（可能大于 1），
 色调映射与 gamma 编码留给后处理阶段的 final 程序统一处理。
 这样做的意义：所有光学混合（泛光、透明度、雾）都在物理正确的
 线性空间里进行，最后才转成显示器能看懂的信号。
================================================================================
*/

/*
================================================================================
 lib/fragment_output.glsl —— gbuffers 片元输出（片元着色器专用）
================================================================================
 所有 gbuffers_* 片元着色器最后都要做同一件事：
   把结果写进 3 张颜色缓冲区（MRT，多渲染目标）。

 本项目使用的缓冲区分配（改动这里之前请先想清楚，因为后处理依赖它）：

   colortex0  场景颜色
              rgb = 已经算完光照和雾的 HDR 颜色
              a   = 透明度（给 _a 半透明程序用，其它时候为 1）

   colortex1  几何缓冲区 G-Buffer
              rg = 视图空间法线的八面体编码（完整球面）
              b  = 天空光等级
              a  = 材质标记（MAT_SOLID / MAT_WATER / ...）

   colortex2  光照缓冲区
              r = 方块光等级
              g = 天空光等级
              b = 阴影系数（1 = 受光，0 = 被遮挡）
              a = 材质类别与贴图亮度，由地形阶段补写

 为什么要拆成三张而不是塞进一张？
   1. 后处理需要的信息（法线、深度）和最终颜色是两种数据，
      混在一起就没法在被泛光污染之后还还原出干净的法线；
   2. 各阶段按寿命复用附件；colortex1 使用 16 位浮点，同时承载透明阶段
      的水面参数与雨层光学深度，colortex2 保留透明颜色的 HDR 范围。

 【只应被 .fsh 引用】—— 它写入了 gl_FragData，顶点着色器里不存在。
================================================================================
*/
#include "/lib/surface/fragment_output_forward.glsl"

/*
================================================================================
 lib/fog.glsl —— 大气雾 / 水下雾
================================================================================
 为什么需要雾？
   1. 它模拟大气散射：远处的物体因为中间隔着厚厚的空气，对比度下降、
      颜色被天空的颜色"洗掉"。
   2. 它藏住边界：玩家的可视距离是有限的，如果远处物体直接"刷"地消失会
      非常突兀。雾让几何体的尽头自然融入天空。

 本实现不依赖游戏的雾参数，而是自己根据视距（far）算一条曲线，
 这样在游戏里调整渲染距离时表现是一致的、可预期的。
================================================================================
*/
#include "/lib/atmosphere/fog_forward.glsl"

/* 薄植被的逆光透射。只对已映射的树叶、草木、庄稼生效，使用日月阴影中
 * 最近投影体的类别和厚度限制透光；实体墙、厚叶团及阴影范围外均不补光。
 * 这是一层薄材质近似，不追踪多次内部散射，也不改变方块透明度。
 */
#include "/lib/lighting/foliage_lighting.glsl"

/* Surface material lighting shares solar transmission and the companion's
 * existing per-light visibility. Local specular is never gated by solar shadow.
 */
#include "/lib/surface/material_lighting.glsl"

/* 资源包驱动的通用不透明表面。材质贴图保持线性数据，颜色由调用者转为线性空间。 */
#include "/lib/surface/pbr_surface_terrain.glsl"

#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
#include "/lib/water_plant_surface.glsl"

// Tag only genuinely axis-aligned raster faces. Derivatives are taken before
// alpha rejection, so a cutout or an adjacent stair cannot tilt this plane.
float waterFaceTag(vec3 viewPosition) {
    vec3 normal = mat3(gbufferModelViewInverse) * cross(dFdx(viewPosition), dFdy(viewPosition));
    float area = length(normal);
    if (area < 1e-12) return 0.0;
    normal /= area;
    if (abs(normal.x) > 0.99995) return normal.x > 0.0 ? 1.0 : 2.0;
    if (abs(normal.y) > 0.99995) return normal.y > 0.0 ? 3.0 : 4.0;
    if (abs(normal.z) > 0.99995) return normal.z > 0.0 ? 5.0 : 6.0;
    return 0.0;
}

void main() {
    float receiverFace = waterFaceTag(vViewPos);
    /* =======================================================================
     * 第一步：材质颜色（Albedo）
     * ====================================================================
     * texture(gtexture, uv) 从方块图集里取出这一点的颜色。
     * 乘 vColor 是因为 MC 把生物群系染色放在顶点颜色里：
     *   草方块在平原偏黄绿、在沼泽偏灰绿，靠的就是这个乘法，
     *   同一张贴图能表现出不同生物群系的样子。
     *
     * albedo（反照率）的物理含义是"表面反射了多少比例的光"，
     * 它与"光照"是相乘的关系 —— 这就是为什么光照模型里到处都乘 albedo。
     */
    vec2 materialUv = pbrParallaxUv(vTexCoord, vViewPos,
        safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0)), vPbrTile);
    vec4 texel = texture(gtexture, materialUv);
    vec4 albedo = vec4(texel.rgb * vColor.rgb, texel.a);
    // separateAo 把原版环境遮蔽放在顶点 alpha，材质 alpha 保持贴图值。
    float occlusion = clamp(vColor.a, 0.0, 1.0);
    // 光照在相同的线性空间中计算；透明度保持原值。
    albedo.rgb = toLinearSpace(albedo.rgb);
    LabPbrMaterial pbr = readPbrSurface(albedo.rgb, materialUv);
    vec3 pbrNormal = pbrSurfaceNormal(safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0)),
        vViewPos, vTexCoord, pbr.tangentNormal);

    /* =======================================================================
     * 第二步：alpha 测试
     * ====================================================================
     * 树叶、草、铁栏杆这类"镂空"贴图，被裁剪掉的部分 alpha 接近 0。
     * 不丢弃它们的话，这些像素会写进深度缓冲，让后面的东西被错误遮挡。
     *
     * alphaTestRef 是游戏传来的阈值（通常是 0.1）。
     * 对 gbuffers_terrain_a（半透明地形）这个值会被置为 0，
     * 于是这一步不会丢弃任何像素，半透明交给 alpha 混合处理。
     */
    if (albedo.a < alphaTestRef) {
        discard;
    }
    if (waterPlantAboveSurface(viewToAbsoluteWorld(vViewPos), vEntityId.x)) {
        discard;
    }

    /* =======================================================================
     * 第三步：准备光照需要的输入
     * ==================================================================== */

    // 法线：视图空间，由顶点着色器插值而来。
    // 对平面方块来说三个顶点法线相同，插值结果仍是同一个方向；
    // 对平滑光照的模型（如台阶的圆弧）插值则会让法线在表面渐变，正是想要的效果。
    vec3 normalView = pbrNormal;

    // 光照贴图坐标：x = 方块光（火把、萤石），y = 天空光（露天程度）。
    vec2 lmCoord = prepareLightmapCoord(vLightmapCoord);

    // 光照贴图颜色：MC 已经烘焙好的环境照明。
    // 火把附近偏橙、露天正午偏白、洞穴深处接近全黑。
    // 直接用它做环境光，比自己凭空造一个"天空光 + 点光源"要自然得多，
    // 而且开销几乎为零 —— 这正是 MC 光照系统的巧妙之处。
    vec3 lmColor = sampleLightmapColor(lmCoord);

    // 到摄像机的距离。视图空间里摄像机在原点，所以直接取长度。
    float viewDistance = length(vViewPos);

    // 材质标记：地形统一标记为"实心"。
    // 如果以后要给树叶、发光方块单独做处理，就在这里按 vEntityId 分类，
    // 改成写入 MAT_FOLIAGE 等其它值，后处理阶段就能识别出来。
    float material = MAT_SOLID;
    vec3 normalWorld = normalize(mat3(gbufferModelViewInverse) * normalView);
    bool foliage = vEntityId.x >= 199.5 && vEntityId.x <= 205.5;
    bool special = vEntityId.x >= 99.5 && vEntityId.x < 199.5;
    if (foliage) material = MAT_FOLIAGE;
    if (normalWorld.y > 0.98 && texel.a > 0.99 && !foliage && !special) {
        material = MAT_WET_GROUND;
    }

    /* =======================================================================
     * 第四步：阴影
     * ====================================================================
     * getShadowFactor() 内部做的事（见 lib/shadow.glsl）：
     *   1. 把畸变后的裁剪空间坐标做透视除法，得到阴影贴图上的 UV 和深度
     *   2. 在 UV 周围采 3x3 个点，比较深度，得到 9 个"受光/被遮挡"的判断
     *   3. 求平均 -> 得到一个 0 到 1 之间的连续系数，软阴影就是这么来的
     */
    vec3 shadow = getSurfaceShadowFactor(vShadowClipPos, normalView,
                                         viewDistance, lmCoord.y);

    /* =======================================================================
     * 第五步：光照
     * ====================================================================
     * computeLighting() 的公式（见 lib/lighting.glsl）：
     *
     *   颜色 = albedo × 环境光(光照贴图)              <- 火把、天空散射
     *        + albedo × 太阳颜色 × (N·L) × 阴影系数    <- 直射阳光
     *
     *   其中 N·L 是法线与光线方向的夹角余弦：
     *     N·L = 1  表面正对太阳，最亮
     *     N·L = 0  表面与光线平行，收不到光（背光面）
     */
    vec3 reflectionSource;
    vec3 color = computePbrLighting(pbr, normalView, lmCoord, shadow,
        occlusion, vViewPos, vTexCoord, reflectionSource);
    vec3 transmittedLight = foliageTransmittedLight(albedo.rgb, normalView, lmCoord, vShadowClipPos,
        vViewPos, vEntityId.x, occlusion);
    color += transmittedLight;
    reflectionSource += transmittedLight;

    /* =======================================================================
     * 第六步：雾
     * ====================================================================
     * 按距离把颜色混合向雾色，让远处自然融入天空。
     * 注意雾是在【线性空间】里混合的，物理上才正确
     * （在 gamma 空间混合会让远处的雾看起来偏暗、发灰）。
     */
    color = applySurfaceFog(color, viewDistance);

    /* =======================================================================
     * 第七步：写出 G-Buffer
     * ====================================================================
     * 一次写入三个渲染目标（MRT）：
     *   colortex0 <- 颜色（HDR）
     *   colortex1 <- 法线、天空光、材质标记
     *   colortex2 <- 方块光、天空光、阴影系数
     * 后处理程序稍后会读这些数据。
     *
     * 通过 alpha 测试的地形片元就是完全不透明的几何体（剔除式方块不做混合），
     * alpha 的低位标记完整几何覆盖，高位标记裁剪式植被，供反射区分前景与后景。
     * 透明贴图已在前面执行裁剪，不能把其边缘小数 alpha 当作几何覆盖率。
     */
    writeGBuffers(color, normalView, lmCoord, shadow, material, foliage ? 3.0 : 1.0);
    // C0 is opaque here. Deferred consumes the tag before publishing scene alpha.
    // Preserve aquatic identity separately from the terrain plane. Refraction
    // still sees the surviving leaves; an air-side reflection cannot hit them.
    float receiverClass = isMaskedTerrainSurface(gtexture, vPbrTile.xy, vPbrTile.zw)
        ? 24.0 : 8.0;
    if (abs(vEntityId.x - 205.0) < 0.5) receiverClass = 16.0;
    fullOut0.a = receiverClass + receiverFace;
    fullOut2.a = pbr.metallic;
    fullOut3 = vec4(pbr.f0, sqrt(pbr.roughness));

}

