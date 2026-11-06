#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;

/*
================================================================================
 gbuffers_weather.fsh —— 雨/雪片元着色器
================================================================================
 雨雪的贴图是半透明的细条纹，靠 alpha 混合叠加到场景上。

 一个常见需求：下雨时整体环境变暗。这里没有在光照里改，
 而是直接在颜色上乘一个系数 —— 因为雨是"覆盖层"，
 它不应该影响场景本身的光照（场景的变暗由天气系统在别处处理）。
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
#include "/lib/surface/fragment_output_weather.glsl"

#if DEBUG_VIEW == 0
/* RENDERTARGETS: 0,1 */
#else
/* RENDERTARGETS: 0 */
#endif
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

/* 世界坐标中的雨滴波环。四个邻域滴点使用解析斜率，避免纹理动画的平铺和跳帧。
 * 半径小于胞元的一半，四邻域足够覆盖；像素足迹过大时连续退出。
 */
#include "/lib/weather/rain_ripples.glsl"

void main() {
    vec4 texel = texture(gtexture, vTexCoord);
    vec4 albedo = texel * vColor;
    // 保留原生雨雪网格的遮挡和范围。雨幕改用窄条与落下的短滴，雪花保留贴图。
    float rain = vRainDraw;
#if ENABLE_REALISTIC_RAIN == 1
    vec3 world = viewToAbsoluteWorld(vViewPos);
    float lane = vTexCoord.x * 3.0;
    vec3 seed = rainImpactHash(floor(world.xz) + floor(lane) * vec2(7.3, 17.1));
    float lateral = abs(fract(lane) - mix(0.2, 0.8, seed.x));
    float width = mix(0.024, 0.045, seed.z);
    float antialias = max(fwidth(lane), 0.003);
    float streak = 1.0 - smoothstep(width - antialias, width + antialias, lateral);
    float fall = fract(world.y * 0.65 + frameTimeCounter * 9.0 + seed.y * 5.0);
    streak *= smoothstep(0.0, 0.04, fall) * (1.0 - smoothstep(0.16, 0.32, fall));
    float rainAlpha = streak * vColor.a * mix(0.38, 0.62, seed.z);
    albedo.a = mix(albedo.a, rainAlpha, rain);
#endif
    // 光照在相同的线性空间中计算；透明度保持原值。
    albedo.rgb = toLinearSpace(albedo.rgb);

    // 雨的条纹贴图里绝大部分是透明的，这一步会丢弃绝大多数像素。
    // 先做 alpha 测试再做光照，能省下大量无用的光照计算。
    if (albedo.a <= 0.001 || albedo.a < alphaTestRef) {
        discard;
    }

    vec3 normalView = vNormalView;
    vec2 lmCoord    = prepareLightmapCoord(vLightmapCoord);
    vec3 lmColor    = sampleLightmapColor(lmCoord);
    float viewDistance = length(vViewPos);

    float shadow = 1.0;   // 雨滴不接收阴影

    // Snow retains the bound sprite and its actual surface illumination.
    vec3 illumination = surfaceAmbient(lmCoord, 1.0)
                      + (getSunLightColor() + getMoonLightColor()) * 0.12;
    float rainIntensity = luma(illumination) * mix(0.6, 1.2, luma(texel.rgb));
    vec3 color = toLinearSpace(rainDropAlbedo()) * rainIntensity;
    if (rain < 0.999) {
        vec3 snow = computeLighting(albedo.rgb, normalView, lmColor, lmCoord, shadow, vViewPos);
        color = mix(applyFog(snow, viewDistance), color, rain);
    }
    // 远处雨丝随雾消隐，避免被雾色重新染成明亮的蓝白条纹。
    albedo.a *= mix(1.0, 0.45 * (1.0 - getFogFactor(viewDistance)), rain);
    // 雨层在云、雾和水体之后统一合成，避免被远处云层再次覆盖。
#if DEBUG_VIEW == 0
    fullOut0 = vec4(color, albedo.a * (1.0 - rain));
#else
    fullOut0 = vec4(color, albedo.a);
#endif
#if DEBUG_VIEW == 0
    // R/G remain the water parameters. B/A are an independent rain layer.
    fullOut1 = rainOverlayMoments(rainIntensity, albedo.a * rain);
#endif
}

