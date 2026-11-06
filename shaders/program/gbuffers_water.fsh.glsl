#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;

/*
 * 半透明水材质：局部光照贴图提供漫反射，天光与不透明阴影限制日/月高光。
 * colortex9 单独保存波浪法线、天光可见度和线性深度，供 composite 计算倒影。
 * 其它半透明方块沿用普通材质光照，不写入水面反射标记。
 */
/* RENDERTARGETS: 0,1,2,9,7 */

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

/* 水面光学与波浪工具。共享 Fresnel、八面体法线编码和连续波浪高度场。
 * 三组正弦分量使用绝对世界坐标保持区块接缝连续，正弦差公式直接求差分法线。
 */
#include "/lib/water/surface_data_forward.glsl"

/* 水面细节法线与像素足迹过滤。几何位移保留 water.glsl 中的长波，细节只改变法线。
 *
 * 为什么不用正弦叠加：有限个正弦之和是周期函数，远看会出现规则条纹，
 * 几组方向不同的正弦交叉后还会形成网格。这里改为四层随机值噪声：
 *   - 每层各自旋转到接近风向的不同角度，避免共用同一套网格轴；
 *   - 沿传播方向较密、沿波峰方向拉长，形成长短不一的波峰，而不是圆斑；
 *   - 波长按约 2 倍递减、振幅更快递减，细碎波纹只做点缀，整体密度较低；
 *   - 各层按深水色散的趋势移动：长波较快、短波较慢，时间上不会整体平移。
 * 噪声导数是解析求得的，每层只需四次哈希，不需要额外的有限差分采样。
 * 无法被当前像素分辨的层逐渐退出，避免远处波纹与高光闪烁。
 */
#include "/lib/water/water_surface.glsl"

/* 世界坐标中的雨滴波环。四个邻域滴点使用解析斜率，避免纹理动画的平铺和跳帧。
 * 半径小于胞元的一半，四邻域足够覆盖；像素足迹过大时连续退出。
 */
#include "/lib/weather/rain_ripples.glsl"

/* 水面局部光照与 GGX 高光；只供片元阶段使用。 */
#include "/lib/water/water_lighting_water_forward.glsl"

/* Surface material lighting shares solar transmission and the companion's
 * existing per-light visibility. Local specular is never gated by solar shadow.
 */
#include "/lib/surface/material_lighting.glsl"

/* 资源包驱动的通用不透明表面。材质贴图保持线性数据，颜色由调用者转为线性空间。 */
#include "/lib/surface/pbr_surface_water_forward.glsl"

uniform sampler2D colortex6;
uniform sampler2D depthtex1;
uniform sampler2D colortex15;
// OptiFine binds the pre-hand depth at unit 12, but its gbuffer uniform setup
// assigns only depthtex0/1. Keep this sampler off the default material unit.
layout(binding=12) uniform sampler2D depthtex2;
#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
#include "/lib/water_face_cache.glsl"
#include "/lib/water_environment.glsl"
#include "/lib/water_interface_ray.glsl"
#include "/lib/water_sheet.glsl"
in float vWaterRestHeight;

// Thin streams use their actual raster plane, including vertical walls and
// undersides. Advect the variation downhill in that plane to connect each fall.
vec4 waterStreamLayer(vec3 world, vec3 face, vec3 view, vec3 illumination, vec3 nativeColour,
                      vec3 biome, float daylight, float directVisibility, float footprint) {
    vec3 downhill = vec3(0.0, -1.0, 0.0) + face * face.y;
    downhill = safeNormalize(downhill, vec3(1.0, 0.0, 0.0));
    vec3 across = safeNormalize(cross(face, downhill), vec3(0.0, 0.0, 1.0));
    vec2 phase = vec2(dot(world, across) * 3.0, dot(world, downhill) * 0.9 - frameTimeCounter * 0.9);
    vec3 waves = waterValueNoise(phase) * (1.0 - smoothstep(0.12, 0.55, footprint));
    float streak = waves.x;
    vec3 filmNormal = normalize(face - 0.025 * waves.y * across - 0.012 * waves.z * downhill);
    if (dot(filmNormal, view) < 0.0) filmNormal = -filmNormal;
    vec3 normalView = mat3(gbufferModelView) * filmNormal;
    vec3 incident = normalize(vViewPos);
    float cosine = clamp(dot(filmNormal, view), 0.0, 1.0);
    // A thin sheet primarily attenuates the background equally in RGB. Use
    // the pond's scattering palette only for the small in-scattered term.
    float thickness = (0.11 + 0.24 * WATER_SURFACE_OPACITY) * mix(1.45, 1.0, cosine);
    thickness *= 1.0 + 0.16 * streak;
    float absorption = 1.0 - exp(-thickness);
    vec3 scatter = waterScatteringAlbedo(biome) * illumination * 0.6 * nativeColour;
    float ior = mix(1.0, WATER_IOR, WATER_REFRACTION_STRENGTH);
    float eta = isEyeInWater == 1 ? ior : 1.0 / ior;
    vec3 inside = refract(incident, normalView, eta);
    bool totalReflection = dot(inside, inside) < 0.001;
    vec3 backing = texelFetch(colortex6, ivec2(gl_FragCoord.xy), 0).rgb;
    vec3 shift = vec3(0.0);
    if (!totalReflection && isEyeInWater == 1) {
        // From inside the water this boundary exits into air once. Keep the
        // outgoing Snell direction all the way to the pre-hand receiver.
        shift = waterSheetTransmission(colortex15, depthtex2, vViewPos, normalView, inside, far, backing);
    } else if (!totalReflection) {
        shift = waterSheetTransmission(colortex6, depthtex1, vViewPos, normalView, inside, 0.24, backing);
    }
    vec3 baseView = mat3(gbufferModelView) * face;
    if (dot(baseView, -incident) < 0.0) baseView = -baseView;
    vec3 mirrorNormal = waterBoundImageNormal(baseView, normalView - baseView);
    vec3 ray = reflect(incident, mirrorNormal);
    vec3 reflected = isEyeInWater == 1 ? scatter : toLinearSpace(skyColor) * daylight;
    ivec2 hit;
    if (waterScreenHit(vViewPos, ray, normalView, 10, hit)) {
        reflected = texelFetch(colortex6, hit, 0).rgb;
    } else {
        vec4 local = sampleWaterEnvironment(vViewPos, ray, normalView);
        if (local.a > 0.0) {
            reflected = local.rgb;
        }
    }
    // Missing screen information changes the radiance source, not Fresnel.
    // A fall must retain its sky/environment reflection when SSR leaves view.
    float sheen = totalReflection ? 1.0 : waterDielectricFresnel(cosine,
        isEyeInWater == 1 ? WATER_IOR : 1.0 / WATER_IOR) * WATER_REFLECTION_STRENGTH;
    float opacity = absorption * (1.0 - sheen) + sheen;
    vec3 radiance = scatter * absorption * (1.0 - sheen) + reflected * sheen + shift * (1.0 - opacity);
    radiance += waterDirectSpecular(normalView, vViewPos, max(WATER_ROUGHNESS, 0.15))
        * directVisibility * WATER_SPECULAR_STRENGTH * WATER_REFLECTION_STRENGTH;
    // The native triangles determine coverage. Vanilla texture alpha is a
    // blend-strength convention, not holes in this physical water interface.
    return vec4(radiance / max(opacity, 0.0001), clamp(opacity, 0.0, 1.0));
}

void main() {
    vec3 worldPosition = viewToAbsoluteWorld(vViewPos);
    float waveFootprint = max(length(dFdx(worldPosition.xz)), length(dFdy(worldPosition.xz)));
    bool movingFluid = abs(vEntityId.x - 106.0) < 0.5;
    bool water = abs(vEntityId.x - WATER_BLOCK_ID) < 0.5 || movingFluid;
    vec3 dx = mat3(gbufferModelViewInverse) * dFdx(vViewPos);
    vec3 dy = mat3(gbufferModelViewInverse) * dFdy(vViewPos);
    dx.y = dFdx(vWaterRestHeight);
    dy.y = dFdy(vWaterRestHeight);
    // The area of a pixel on a flow face shrinks near the eye. Normalise the
    // edges first so close vertical faces keep their orientation.
    vec3 rasterFace = safeNormalize(cross(dx / max(length(dx), 1e-12), dy / max(length(dy), 1e-12)),
        vec3(0.0, 1.0, 0.0));
    float streamFootprint = max(length(dx), length(dy));
    vec2 materialUv = water ? vTexCoord : pbrParallaxUv(vTexCoord, vViewPos,
        safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0)), vPbrTile);
    vec4 texel = texture(gtexture, materialUv);
#if ENABLE_WATER_TEXTURE == 0
    if (water) {
        texel.rgb = vec3(1.0);
    }
#endif
    vec3 albedoColor = water
        ? toLinearSpace(texel.rgb) * waterScatteringAlbedo(vColor.rgb)
        : toLinearSpace(texel.rgb * vColor.rgb);
    vec4 albedo = vec4(albedoColor, texel.a * vColor.a);
    LabPbrMaterial pbr = readPbrSurface(albedoColor, materialUv);
    bool reflective = max(max(pbr.f0.r, pbr.f0.g), pbr.f0.b) > 0.0001
        && ENABLE_MATERIAL_REFLECTIONS == 1 && MATERIAL_REFLECTION_STRENGTH > 0.0;
    bool glass = !water && reflective;
    vec3 geometricNormal = safeNormalize(vNormalView, vec3(0.0, 1.0, 0.0));
    vec3 mappedNormal = pbrSurfaceNormal(geometricNormal, vViewPos, vTexCoord, pbr.tangentNormal);
    if (!glass && (albedo.a <= 0.001 || albedo.a < alphaTestRef)) {
        discard;
    }

    vec3 normalView = water ? geometricNormal : mappedNormal;
    bool horizontal = abs(rasterFace.y) > 0.9998;
    bool topSurface = water && horizontal && (isEyeInWater == 1 || (!movingFluid && rasterFace.y > 0.0));
    bool stream = water && !topSurface;
    if (stream) normalView = mat3(gbufferModelView) * rasterFace;
    if (topSurface) {
        vec3 waveNormalWorld = vec3(0.0, 1.0, 0.0);
#if ENABLE_WATER_WAVES == 1
        waveNormalWorld = waterSurfaceNormal(worldPosition.xz, frameTimeCounter, waveFootprint);
#endif
        // 雨滴圆环独立于风浪开关，平静水面仍可接收落雨扰动。
        vec2 rainSlope = rainRippleSlope(worldPosition.xz, frameTimeCounter, waveFootprint)
            * smoothstep(0.95, 0.995, waterSkyLevel(vLightmapCoord.y));
        waveNormalWorld = normalize(waveNormalWorld + vec3(-rainSlope.x, 0.0, -rainSlope.y));
        float orientation = isEyeInWater == 1 ? -1.0 : 1.0;
        vec3 waveView = mat3(gbufferModelView) * waveNormalWorld * orientation;
        float grazing = abs(dot(normalView, normalize(-vViewPos)));
        // 细节法线没有独立几何遮挡，掠射时限制斜率，避免假背面产生黑色空洞。
        float slopeWeight = mix(0.35, 1.0, smoothstep(0.02, 0.20, grazing));
        normalView = safeNormalize(mix(normalView, waveView, slopeWeight), normalView);
    }

    vec2 lmCoord = prepareLightmapCoord(vLightmapCoord);
    vec3 lmColor = sampleLightmapColor(lmCoord);
    float viewDistance = length(vViewPos);
    float skyVisibility = waterSkyVisibility(lmCoord.y);
    float directSky = smoothstep(0.60, 0.96, waterSkyLevel(lmCoord.y));
    float shadow = 1.0;
    if (directSky > 0.001) {
        shadow = waterOpaqueShadow(vShadowClipPos, normalView, viewDistance);
        shadow *= cloudProjectedShadow(viewToAbsoluteWorld(vViewPos),
            normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
    }
    float directVisibility = shadow * directSky;
    vec3 color;
    vec3 scatteringRadiance = vec3(0.0);
    if (stream) {
        vec3 illumination = waterDiffuse(vec3(1.0), normalView, lmCoord, directVisibility, vViewPos);
        vec3 view = normalize(mat3(gbufferModelViewInverse) * -vViewPos);
        vec4 layer = waterStreamLayer(worldPosition, rasterFace, view, illumination, texel.rgb,
            vColor.rgb, skyVisibility, directVisibility, streamFootprint);
        // The backing has already travelled through the camera fog. Fade the
        // film's contrast with distance so it does not add a second fog colour.
        color = layer.rgb;
        albedo.a = layer.a * (1.0 - getFogFactor(viewDistance));
    } else if (water) {
        color = waterDiffuse(albedo.rgb, normalView, lmCoord, directVisibility, vViewPos);
        scatteringRadiance = color;
        albedo.a *= WATER_SURFACE_OPACITY;
        // 合成阶段会在最终水面颜色上计算 GGX 高光；这里的颜色会被覆盖。
        // 封闭水域的散射颜色也必须随当地光照衰减。
        // 与 waterScatteringAlbedo 一致的暗青色，不再是偏重的蓝。
        vec3 scatter = mix(lmColor * vec3(0.06, 0.20, 0.23), getFogColor(), skyVisibility);
        color = mix(color, scatter, getFogFactor(viewDistance));
    } else {
        // 透明介质的底色保留原生alpha，反射/高光由下方独立光学层统一处理。
        vec3 view = safeNormalize(-vViewPos, normalView);
        vec3 tangent = pbrGlossTangent(normalView, vViewPos, vTexCoord);
        vec4 layer = transparentPbrLayer(pbr, normalView, tangent, vViewPos, view, lmCoord, shadow, albedo.a);
        color = layer.rgb;
        albedo.a = layer.a;
    }

    // 光学密度保存在 colortex7，低 alpha 不能让加载器丢掉水面几何数据。
    float outputAlpha = topSurface ? max(albedo.a, alphaTestRef) : albedo.a;
    writeGBuffers(color, normalView, lmCoord, shadow, water ? MAT_WATER : MAT_SOLID, outputAlpha);
    // 水面数据以二值 alpha 替换，玻璃输出零值并保留它；玻璃颜色另存预乘层。
    // 线性深度位于 B，alpha 专门用于覆盖标记，避免透明混合破坏水面深度。
    fullOut3 = topSurface
        ? vec4(encodeWaterNormal(normalView), max(-vViewPos.z, 0.0), 1.0) : vec4(0.0);
    fullOut4 = topSurface && isEyeInWater != 1 ? vec4(scatteringRadiance, 1.0) : vec4(0.0);
#if DEBUG_VIEW == 0
    // Below water the scatter attachment is free. Associate the transmitted
    // transparent layer with the actual raster plane which wrote its colour.
    if (isEyeInWater == 1) {
        if (!topSurface && outputAlpha > 0.001) {
            vec3 layerNormal = stream ? normalView : geometricNormal;
            vec2 plane = encodeWaterNormal(layerNormal);
            vec3 axes = abs(mat3(gbufferModelViewInverse) * layerNormal);
            int axis = axes.x > max(axes.y, axes.z) ? 0 : (axes.y > axes.z ? 1 : 2);
            float coordinate = worldPosition[axis] - floor(cameraPosition[axis]);
            float gridPlane = round(coordinate * 16.0) / 16.0;
            if (axes[axis] > 0.99995 && abs(gridPlane - coordinate) < 0.0002 && abs(gridPlane) < 64.0) {
                plane = vec2(2 + axis, gridPlane);
            }
            fullOut4 = vec4(plane, max(-vViewPos.z, 0.0), 1.0);
        }
    }
    fullOut1 = topSurface ? vec4(skyVisibility, albedo.a, 0.0, 1.0) : vec4(0.0);
    fullOut2 = topSurface ? vec4(0.0) : vec4(color * outputAlpha, outputAlpha);
#endif
}

