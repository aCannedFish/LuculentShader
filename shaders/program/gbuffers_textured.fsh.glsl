#include "/lib/surface/opaque_targets.glsl"
#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;

/*
================================================================================
 gbuffers_textured.fsh —— 带贴图、不受阳光直射影响的几何体
================================================================================
 与 basic 的区别：
   * 材质颜色 = 贴图 × 顶点颜色
   * 只乘光照贴图的颜色，不做直射光/阴影计算 —— 这类几何体（粒子等）
     在 MC 里本来就不投射阴影，硬加上阴影反而会出现"粒子被自己的影子切一半"
     的怪异现象。
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

/* Rain impacts use the same neutral illumination and palette as rain streaks.
 * Classification follows gtexture and vertex tint together; other particle hues
 * retain their ordinary lighting, including bright soul-fire textures.
 */
#include "/lib/weather/rain_particles.glsl"

void main() {
    // 1. 材质颜色 = 图集上的贴图 × 顶点染色
    //    texture(采样器, 坐标) 是 GLSL 120 的纹理采样函数
    //    （GLSL 330 之后改名为 gtexture()，本项目统一用 120 的写法）
    vec4 texel = texture(gtexture, vTexCoord);
    vec4 albedo = texel * vColor;
    vec3 rawAlbedo = albedo.rgb;
    // 光照在相同的线性空间中计算；透明度保持原值。
    albedo.rgb = toLinearSpace(albedo.rgb);

    // 2. alpha 测试：透明像素丢弃
    if ((isParticleStage() && albedo.a <= 0.001) || albedo.a < alphaTestRef) {
        discard;
    }

    // 3. 只受环境光影响：直接乘光照贴图颜色。
    //    这样夜里/洞里粒子会自然变暗，但不会被阳光的阴影切成两半。
    vec2 lmCoord = prepareLightmapCoord(vLightmapCoord);
    vec3 lmColor = sampleLightmapColor(lmCoord);
    vec3 color = albedo.rgb * lmColor * AMBIENT_STRENGTH;
    vec4 rainLayer;
    color = shadeRainParticle(color, rawAlbedo, lmCoord, albedo.a, rainLayer);

    // 4. 雾
    float viewDistance = length(vViewPos);
    color = applyRainParticleFog(color, rawAlbedo, viewDistance, albedo.a, rainLayer);

    // 5. 写出。阴影系数填 1（不受阴影影响），材质标记用 SOLID。
    //    即使不参与阴影，也要往 colortex2 写字，
    //    否则缓冲区里会残留上一帧的数据，调试视图会看到脏东西。
    writeGBuffers(color, vNormalView, lmCoord, 1.0, isParticleStage() ? MAT_BILLBOARD : MAT_SOLID, albedo.a);
}

