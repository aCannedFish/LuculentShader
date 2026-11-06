// Underwater.
#ifndef LIB_UNDERWATER_GLSL
#define LIB_UNDERWATER_GLSL

/* Shared viewport shape for clouds, air scattering and underwater shafts.
 * Buffers keep full attachment sizes; generation and reconstruction must agree
 * on the active lower-left region, including odd internal render dimensions.
 */
#include "/lib/atmosphere/volume_resolution.glsl"

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

uniform sampler2D depthtex2;
SIMPLE_VARYING vec3 vUnderwaterTint;
SIMPLE_VARYING vec3 vUnderwaterScatter;
#define underwaterOpaqueSource colortex6

/* Reconstruct the reduced underwater shaft field using optical path depth.
 * The first texel is frame metadata and never contributes shaft radiance. */
#include "/lib/water/water_shafts_filter.glsl"

// 反射源刻意把天空留黑；水下出射必须从天空表恢复背景，并让实际几何继续遮挡它。
vec3 underwaterBackgroundColor(vec2 uv) {
    if (texture(depthtex1, uv).r < 0.999999) {
        return texture(underwaterOpaqueSource, uv).rgb;
    }
    vec3 direction = skyViewDirection(uv);
    vec4 cloud = cloudEnvironment(direction);
    return cloud.rgb + skyRadiance(direction) * (1.0 - cloud.a);
}

#ifdef WATER_TRANSMISSION_PASS
#include "/lib/labpbr_decode.glsl"
#include "/lib/pbr_height.glsl"
#include "/lib/transparent_pbr.glsl"
#include "/lib/water_glass.glsl"
#include "/lib/water_exit.glsl"
#endif

// 全反射只查询水下场景。离屏或无命中时使用受当地照明控制的水色。
vec3 underwaterInterfaceReflection(vec3 interfaceView, vec3 direction, float waterHeight) {
    vec3 fallback = vUnderwaterScatter
        + vec3(0.004, 0.012, 0.018) * UNDERWATER_MIN_VISIBILITY;
    vec3 down = mat3(gbufferModelView) * vec3(0.0, -1.0, 0.0);
    ScreenReflectionHit hit = traceAdaptiveReflectionDetailed(underwaterOpaqueSource, depthtex1,
        interfaceView + down * 0.025, direction, 0.03, 24.0,
        min(WATER_REFLECTION_STEPS, 16), vec4(down, 0.02 - dot(down, interfaceView)));
    if (hit.coverage <= 0.0) {
        return fallback;
    }
    float depth = texture(depthtex1, hit.uv).r;
    vec3 world = viewToAbsoluteWorld(screenToView(hit.uv, min(depth, 0.99999)));
    if (depth >= 0.999999 || world.y > waterHeight + 0.02) {
        return fallback;
    }
    vec3 radiance = texture(underwaterOpaqueSource, hit.uv).rgb;
    return mix(fallback, applyUnderwaterVolume(radiance, hit.distance,
        vUnderwaterTint, vUnderwaterScatter), hit.coverage);
}

vec4 applyUnderwaterOptics(vec2 uv) {
    float eyeDepth = estimateUnderwaterDepth();
    float opaqueDepth = texture(depthtex1, uv).r;
    // 天空只需要方向；避免在无限远投影的 depth=1 处除以零。
    vec3 opaquePosition = screenToView(uv, opaqueDepth < 0.999999 ? opaqueDepth : 0.5);
    vec3 opaqueWorld = viewToAbsoluteWorld(opaquePosition);
    vec4 surface = waterSurfaceAtPixel(colortex9, ivec2(gl_FragCoord.xy));
    float path = underwaterVisiblePath(uv, opaqueDepth, surface.a, eyeDepth);
    float sceneDistance = opaqueDepth < 0.999999 ? length(opaquePosition) : far;
    vec3 rayWorld = skyViewDirection(uv);
    float waterHeight = cameraPosition.y + eyeDepth;
    float aboveGeometry = surface.a > 0.001 || opaqueDepth >= 0.999999 ? 1.0
        : smoothstep(waterHeight + 0.015, waterHeight + 0.20, opaqueWorld.y);
    float airCoverage = smoothstep(0.02, 0.20, sceneDistance - path)
                      * smoothstep(0.01, 0.08, rayWorld.y) * aboveGeometry;
    vec3 interfaceWorld = cameraPosition + rayWorld * path;
    float footprint = max(length(dFdx(interfaceWorld.xz)), length(dFdy(interfaceWorld.xz)));
    // 优先使用原生水面写入的同一套细节法线，波峰与临界角边界一起运动。
    vec3 waveNormal = vec3(0.0, 1.0, 0.0);
#if ENABLE_WATER_WAVES == 1
    waveNormal = waterSurfaceNormal(interfaceWorld.xz, frameTimeCounter, footprint);
#endif
    // 原生法线也包含独立落雨涟漪；关闭风浪时仍保留这些界面扰动。
    if (surface.a > 0.001) {
        vec3 captured = mat3(gbufferModelViewInverse) * decodeWaterNormal(surface.xy);
        waveNormal = captured * (captured.y < 0.0 ? -1.0 : 1.0);
    }
    vec3 interfaceView = surface.a > 0.001 ? waterSurfacePosition(uv, surface.a)
                                          : worldToView(interfaceWorld - cameraPosition);
#ifdef WATER_TRANSMISSION_PASS
    // Prepare only the air side here. The hand-free depth and the forward
    // transparent planes are still available before C7 changes roles.
    float cosine = clamp(dot(rayWorld, waveNormal), 0.0, 1.0);
    float discriminant = 1.0 - WATER_IOR * WATER_IOR * (1.0 - cosine * cosine);
    float edgeWidth = max(fwidth(discriminant) * 1.5, 0.008);
    float window = smoothstep(-edgeWidth, edgeWidth, discriminant);
    float reflectance = waterDielectricFresnel(cosine, WATER_IOR);
    vec3 air = vec3(0.0);
    float transmission = 0.0;
    if (airCoverage > 0.001 && window > 0.001 && discriminant > 0.0) {
        vec3 airDirection = normalize(refract(rayWorld, -waveNormal, WATER_IOR));
        vec3 sampleDirection = normalize(mix(rayWorld, airDirection, WATER_REFRACTION_STRENGTH));
        vec2 radianceUv;
        bool inside;
        air = waterExitRadiance(uv, interfaceView, sampleDirection, radianceUv, inside);
#if DEBUG_VIEW == 0
        if (rainStrength > 0.001 && inside) {
            bool waterPresent = texture(colortex9, radianceUv).a > 0.5;
            air = applyRainOverlay(air, waterScreenParameters(radianceUv), waterPresent);
        }
#endif
        transmission = (1.0 - reflectance) * window;
    }
    return vec4(air, transmission);
#else
    vec3 radiance = texture(colortex0, uv).rgb;
    if (texture(colortex9, uv).a > 0.5) {
        radiance = applyTransparentLayer(underwaterBackgroundColor(uv), waterScreenLayer(uv));
    }
    vec3 normalWorld = waterReceiverNormal(opaqueWorld);
    if (opaqueDepth < 0.999999) {
        float skyVisibility = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
        radiance *= waterCausticGain(opaqueWorld, normalWorld, waterHeight, skyVisibility);
    }
    if (airCoverage > 0.001) {
        vec3 reflectedDirection = mat3(gbufferModelView) * reflect(rayWorld, waveNormal);
        vec3 reflection = underwaterInterfaceReflection(interfaceView, reflectedDirection, waterHeight);
        vec4 air = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0);
        radiance = mix(radiance, mix(reflection, air.rgb, air.a), airCoverage);
    }
    vec3 result = applyUnderwaterVolume(radiance, path, vUnderwaterTint, vUnderwaterScatter);
    result += sampleWaterShafts(uv, path);
    return vec4(result, 1.0);
#endif
}

#endif
