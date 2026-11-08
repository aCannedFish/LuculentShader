// Lighting for volume air.
#ifndef LIB_LIGHTING_GLSL
#define LIB_LIGHTING_GLSL

/*
 * color_space.glsl —— 游戏颜色输入的显示空间转换。
 *
 * 贴图、顶点色、天空色和雾色由游戏按显示颜色提供。它们参与光照、
 * 雾和泛光之前，先转到线性空间；final.fsh 最后再编码回显示空间。
 * 这里使用与 lib/tonemap.glsl 相配的 gamma 2.2 近似。
 */
#include "/lib/core/color_space.glsl"

/*
 * Minecraft 光照贴图的连续采样与光源分离。
 * 在相邻等级的纹素中心手动插值，避免加载器的最近邻采样造成亮度台阶。
 * 方块光从无天光的行中提取，保留原版传播和遮挡，同时避免白天天光饱和将火把光压掉。
 */
#include "/lib/lighting/lightmap_forward.glsl"

/*
 * Spherical atmosphere integration in kilometres. Rayleigh, aerosol scattering
 * and ozone absorption share one density model. A small sky-view lookup is
 * rebuilt before transparent geometry; higher scattering orders are approximated
 * by a modest isotropic source. No compute shader or high-dimensional LUT is used.
 */
#include "/lib/atmosphere/atmosphere_forward.glsl"

/*
 * Companion-provided light positions, independent cube-face shadows and diffuse
 * radiance volumes. All data remains linear HDR. Missing companion data selects
 * the existing Minecraft light-field fallback through companionReady = 0.
 * Block-light energy and wall occlusion always come from the native light field;
 * the companion supplies emitter hue (hue volume) and point-light visibility.
 */
#include "/lib/lighting/companion_lighting_forward.glsl"

/* 本文件用到的 uniform（全部在 lib/uniforms.glsl 中声明）：
 *   sunPosition               太阳在视图空间的方向（长度约 100）
 *   moonPosition              月亮在视图空间的方向
 *   gbufferModelViewInverse   视图空间 -> 世界空间，用来求太阳相对地平线的高度
 *   skyColor                  天空颜色，用作环境光染色
 */

/* ---------------------------------------------------------------------------
 * 太阳几何
 * ------------------------------------------------------------------------ */

// 太阳在世界空间中的方向。
// mat3(...) 取 4x4 矩阵的左上 3x3 部分，等于只做旋转、不做平移。
vec3 getSunDirWorld() {
    return safeNormalize(mat3(gbufferModelViewInverse) * sunPosition, vec3(0.0, 1.0, 0.0));
}

// 太阳相对地平线的高度角：+1 = 正头顶，0 = 地平线，-1 = 正下方（午夜）。
// 这是判断昼夜、决定光照颜色与强度的核心变量。
float getSunHeight() {
    return getSunDirWorld().y;
}

// 白天的程度：0 = 完全夜晚，1 = 完全白天。
// smoothstep 让日出/日落有一个平滑的过渡带，而不是突然切换。
// 让暮光区覆盖地平线两侧，避免太阳刚越过地平线就骤然变色。
float getDayFactor() {
#if SIMPLE_DIMENSION != 0
    return 1.0;
#else
    return smoothstep(-0.12, 0.16, getSunHeight());
#endif
}

float getNightFactor() {
#if SIMPLE_DIMENSION != 0
    return 0.0;
#else
    return 1.0 - smoothstep(-0.16, 0.12, getSunHeight());
#endif
}

/* ---------------------------------------------------------------------------
 * 光源方向与颜色
 * ------------------------------------------------------------------------ */

// 阴影贴图当前使用的光源方向，由加载器提供。
// 太阳与月亮大致相反，不能直接插值两者的方向：暮光时会互相抵消。
vec3 getLightDirView() {
    return safeNormalize(shadowLightPosition, vec3(0.0, 1.0, 0.0));
}

// 日光颜色在低太阳高度时变暖；亮度随暮光平滑淡入。
vec3 getSunLightColor() {
#if SIMPLE_DIMENSION != 0
    return vec3(0.0);
#else
    // 直射光须与实际阴影光源的半球一致；暮光环境光仍保留较宽的昼夜过渡。
    float elevation = getSunHeight();
    return atmosphereDirectTransmittance(elevation)
         * smoothstep(0.0, 0.04, elevation) * SUNLIGHT_STRENGTH
         * mix(1.0, 0.20, weatherRainAmount());
#endif
}

// 月光独立淡出，避免把两侧光源方向混成零向量。
vec3 getMoonLightColor() {
#if SIMPLE_DIMENSION != 0
    return vec3(0.0);
#else
    return vec3(0.80, 0.86, 1.00) * MOONLIGHT_STRENGTH
         * smoothstep(0.0, 0.04, skyMoonDirection().y) * getNightFactor()
         * (0.08 + 0.92 * lunarIlluminatedFraction()) * mix(1.0, 0.35, weatherRainAmount());
#endif
}

// 环境光颜色：天空的散射光。
// 直接把 skyColor 拿来用效果太艳，和光照贴图做插值后更接近 MC 的观感。
vec3 getAmbientColor(vec3 lmColor) {
    vec3 skyLinear = toLinearSpace(skyColor);
    return mix(lmColor, skyLinear * luma(lmColor), SKY_TINT)
         * AMBIENT_STRENGTH;
}

/* ---------------------------------------------------------------------------
 * 主光照函数
 * ------------------------------------------------------------------------ */

/*
 * 计算一个不透明表面的最终颜色。
 *
 * 参数：
 *   albedo        表面反照率（贴图颜色 × 顶点颜色）
 *   normalView    视图空间法线，必须已归一化
 *   lmCoord       光照贴图坐标，x = 方块光等级，y = 天空光等级，范围 [0,1]
 *   shadowFactor  阴影系数，1 = 完全受光，0 = 完全被遮挡
 *
 * 返回值：线性空间的颜色，可能大于 1（HDR），由后处理阶段负责压回显示范围。
 */
// 天空散射接收环境遮蔽；局部光独立累加，太阳阴影不会削弱火把的辐射。
vec3 surfaceAmbient(vec2 lmCoord, float occlusion) {
#if SIMPLE_DIMENSION != 0
    // Direction-dependent dimension fill is added by surfaceAmbientAt().
    return blockLightRadiance(lmCoord) * mix(clamp(occlusion, 0.0, 1.0), 1.0, 0.80);
#endif
    vec3 local = blockLightRadiance(lmCoord);
    vec3 sky = skyLightRadiance(lmCoord);
    // 天空颜色只提供色温；归一亮度后再染色，避免一次颜色插值又压暗漫射能量。
    vec3 skyInput = toLinearSpace(skyColor);
    float skyLuminance = luma(skyInput);
    vec3 skyHue = skyLuminance > 0.0001 ? skyInput / skyLuminance : vec3(1.0);
    skyHue = weatherSkyRadiance(skyHue);
    skyHue /= max(luma(skyHue), EPSILON);
    vec3 skyTinted = sky * mix(vec3(1.0), skyHue, SKY_TINT);
    float localOcclusion = mix(clamp(occlusion, 0.0, 1.0), 1.0, 0.80);
    vec3 deepAmbient = isEyeInWater == 1
        ? vec3(0.60, 0.80, 1.0) * UNDERWATER_MIN_VISIBILITY : vec3(0.0);
    float skyVisibility = smoothstep(0.08, 0.85, lightmapLevel(lmCoord.y));
    // 夜间天空散射保持偏冷，形成稳定的暗部基底；方块暖光独立叠加。
    vec3 nightTint = vec3(0.76, 0.86, 1.0);
    nightTint /= luma(nightTint);
    skyTinted *= mix(vec3(1.0), nightTint, getNightFactor());
    skyTinted *= mix(1.0, 0.88, weatherRainAmount());
    vec3 nightAmbient = nightTint * NIGHT_AMBIENT_STRENGTH
                      * getNightFactor() * skyVisibility;
    float skyStrength = mix(0.08, 0.56, getDayFactor());
    return (lightmapDarkFloor() * occlusion + deepAmbient * occlusion + nightAmbient * occlusion
            + skyTinted * occlusion * skyStrength)
         * AMBIENT_STRENGTH + local * localOcclusion;
}

// 方块光的传播与能量始终来自原版光照场；配套数据只提供色相与点光可见度。
vec3 surfaceAmbientAt(vec2 lmCoord, float occlusion, vec3 normalView, vec3 viewPosition) {
    vec3 ambient = surfaceAmbient(lmCoord, occlusion);
    float localOcclusion = mix(clamp(occlusion, 0.0, 1.0), 1.0, 0.80);
    vec3 nativeBlock = blockLightRadiance(lmCoord);
    ambient += (companionBlockLight(viewPosition, normalView, lmCoord, nativeBlock) - nativeBlock)
             * localOcclusion;
    ambient += companionIndirect(viewPosition, normalView) * mix(occlusion, 1.0, 0.5);
    // 为无天光的矿洞保留可导航亮度；已有照明达到目标时不继续增亮。
    vec3 normalWorld = normalize(mat3(gbufferModelViewInverse) * normalView);
    #if SIMPLE_DIMENSION != 0
    ambient += dimensionAmbient(normalWorld) * occlusion * AMBIENT_STRENGTH;
#endif
#if SIMPLE_DIMENSION == 0
    float exposure = smoothstep(0.08, 0.85, lightmapLevel(lmCoord.y));
    ambient += twilightIrradiance(normalWorld) * exposure * occlusion * AMBIENT_STRENGTH;
#endif
    float shape = 0.75 + 0.25 * max(normalWorld.y, 0.0);
    float contact = mix(0.55, 1.0, clamp(occlusion, 0.0, 1.0));
    float target = MIN_AMBIENT_LIGHT * shape * contact;
    ambient += vec3(max(target - luma(ambient), 0.0));
    return ambient;
}

// shadowFactor 为日月光的 RGB 传递：彩色玻璃染色，发光方块照亮自身投影。
vec3 computeSurfaceLighting(vec3 albedo, vec3 normalView, vec2 lmCoord,
                           vec3 shadowFactor, float occlusion, vec3 viewPosition) {
#if SIMPLE_DIMENSION != 0
    return albedo * surfaceAmbientAt(lmCoord, occlusion, normalView, viewPosition);
#else
    vec3 sunDir = safeNormalize(sunPosition, vec3(0.0, 1.0, 0.0));
    vec3 moonDir = safeNormalize(moonPosition, vec3(0.0, 1.0, 0.0));
    float skyLevel = lightmapLevel(lmCoord.y);
    float directVisibility = smoothstep(0.60, 0.96, skyLevel);
    vec3 direct = getSunLightColor() * max(dot(normalView, sunDir), 0.0)
                + getMoonLightColor() * max(dot(normalView, moonDir), 0.0);
    float cloudVisibility = 1.0;
    // 只为实际能到达接收面的日月直射积分云影。背向当前光源、全遮挡与零强度
    // 都没有云影贡献；局部方块光和 GI 仍独立计算。保留非零透射色，避免丢失玻璃滤色。
    if (directVisibility > 0.001 && any(greaterThan(direct * shadowFactor, vec3(0.0)))) {
        vec3 world = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz + cameraPosition;
        cloudVisibility = cloudProjectedShadow(world, normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
    }
    direct *= cloudVisibility;
    vec3 illumination = surfaceAmbientAt(lmCoord, occlusion, normalView, viewPosition)
                      + direct * shadowFactor * directVisibility;
    return albedo * illumination;
#endif
}

vec3 computeSurfaceLighting(vec3 albedo, vec3 normalView, vec2 lmCoord,
                           float shadowFactor, float occlusion, vec3 viewPosition) {
    return computeSurfaceLighting(albedo, normalView, lmCoord, vec3(shadowFactor), occlusion, viewPosition);
}

// 保留普通几何体的调用接口；地形额外传入已分离的原版 AO。
vec3 computeLighting(vec3 albedo, vec3 normalView, vec3 lmColor,
                     vec2 lmCoord, vec3 shadowFactor, vec3 viewPosition) {
    return computeSurfaceLighting(albedo, normalView, lmCoord, shadowFactor, 1.0, viewPosition);
}

vec3 computeLighting(vec3 albedo, vec3 normalView, vec3 lmColor,
                     vec2 lmCoord, float shadowFactor, vec3 viewPosition) {
    return computeSurfaceLighting(albedo, normalView, lmCoord, vec3(shadowFactor), 1.0, viewPosition);
}

/* ---------------------------------------------------------------------------
 * 高光（Blinn-Phong 近似）
 *   只在需要"湿润/光滑"观感的表面调用，例如水面和冰。
 *   真正的 PBR 会用 GGX 分布 + 几何遮蔽项，这里先给出最简单的版本。
 * ------------------------------------------------------------------------ */
vec3 computeSpecular(vec3 normalView, vec3 viewPos, vec3 specularColor, float glossiness) {
    // 当前水面高光只模拟太阳，并在调用方随日光权重淡出。
    // 直接取太阳方向，可避免阴影贴图切换到月亮时高光跳变。
    vec3 lightDirView = safeNormalize(sunPosition, vec3(0.0, 1.0, 0.0));

    // 视线方向：从表面指向摄像机。视图空间里摄像机就在原点。
    vec3 viewDir = safeNormalize(-viewPos, vec3(0.0, 0.0, 1.0));

    // 半程向量：光线方向与视线方向的角平分线。
    // 它与法线的夹角越小，说明高光越强 —— 这是 Blinn-Phong 相对
    // 原始 Phong 模型的改进，能避免掠射角下的高光断裂。
    vec3 halfDir = safeNormalize(lightDirView + viewDir, normalView);

    float NdotH = clamp(dot(normalView, halfDir), 0.0, 1.0);

    // glossiness 越大，高光越集中越锐利。指数运算开销不高，可以放心用。
    return specularColor * pow(NdotH, glossiness);
}

#endif  // LIB_LIGHTING_GLSL
