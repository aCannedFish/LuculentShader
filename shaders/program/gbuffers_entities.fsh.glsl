#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* RENDERTARGETS: 0,1,2,14,15 */

/*
================================================================================
 gbuffers_entities.fsh —— 实体片元着色器
================================================================================
 与地形的区别只有两点：
   1. 需要叠加 entityColor —— 生物受伤时全身闪红，
      游戏不改贴图，而是通过这个 uniform 传递"叠加色 + 强度"。
   2. 材质标记写成 MAT_ENTITY，方便后处理区分处理
      （例如给实体加轮廓光、或者做描边）。
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

/* 资源包驱动的通用不透明表面。材质贴图保持线性数据，颜色由调用者转为线性空间。 */
#include "/lib/surface/pbr_surface_forward.glsl"

void main() {
    // 1. 材质颜色：贴图 × 顶点染色。
    //    生物的皮肤颜色、羊毛颜色、马的颜色等都在 vColor 里。
    vec2 materialUv = pbrParallaxUv(vTexCoord, vViewPos,
        safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0)), vPbrTile);
    vec4 albedo = texture(gtexture, materialUv) * vColor;
    // 光照在相同的线性空间中计算；透明度保持原值。
    albedo.rgb = toLinearSpace(albedo.rgb);
    LabPbrMaterial pbr = readPbrSurface(albedo.rgb, materialUv);
    vec3 pbrNormal = pbrSurfaceNormal(safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0)),
        vViewPos, vTexCoord, pbr.tangentNormal);

    // 2. 受伤闪红。放在 alpha 测试之前也没关系，
    //    但放在之后可以少算一次被丢弃的像素，所以放在后面。
    albedo = applyEntityColor(albedo);

    if (albedo.a < alphaTestRef) {
        discard;
    }

    // 3. 光照
    vec3 normalView = pbrNormal;
    vec2 lmCoord    = prepareLightmapCoord(vLightmapCoord);
    vec3 lmColor    = sampleLightmapColor(lmCoord);
    float viewDistance = length(vViewPos);

    vec3 shadow = getShadowFactor(vShadowClipPos, normalView, viewDistance);
    vec3 reflectionSource;
    pbr.albedo = albedo.rgb;
    vec3 color = computePbrLighting(pbr, normalView, lmCoord, vec3(shadow),
        1.0, vViewPos, vTexCoord, reflectionSource);

    // 4. 雾 + 写出
    color = applySurfaceFog(color, viewDistance);

    writeGBuffers(color, normalView, lmCoord, shadow, MAT_ENTITY, albedo.a);
    fullOut2.a = pbr.metallic;
    fullOut3 = vec4(pbr.f0, sqrt(pbr.roughness));
}

