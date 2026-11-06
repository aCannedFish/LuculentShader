#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* composite.fsh: half-resolution cloud radiance and optical opacity. */
/* RENDERTARGETS: 4 */
/*
 * Single-scattering volumetric cloud integration with approximate multiple
 * scattering. Main sky clouds render at half resolution; reflections use fewer
 * samples. Empty regions skip lighting and dense rays terminate early. A finite
 * cylindrical horizon bounds grazing rays before any density/noise sampling.
 */
#include "/lib/atmosphere/clouds_volume_air.glsl"

/* Shared viewport shape for clouds, air scattering and underwater shafts.
 * Buffers keep full attachment sizes; generation and reconstruction must agree
 * on the active lower-left region, including odd internal render dimensions.
 */
#include "/lib/atmosphere/volume_resolution.glsl"

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_forward.glsl"

/* 水面光学与波浪工具。共享 Fresnel、八面体法线编码和连续波浪高度场。
 * 三组正弦分量使用绝对世界坐标保持区块接缝连续，正弦差公式直接求差分法线。
 */
#include "/lib/water/surface_data_volumes.glsl"

uniform sampler2D depthtex1;
uniform sampler2D colortex9;
uniform sampler2D colortex1;

#include "/lib/water_entry_grid.glsl"
uniform sampler2D shadowtex1;

// Estimate blocker distance in light space, then integrate a disk matching
// the apparent sun. High leaves cast a wider penumbra than a low ledge.
float entrySolarCoverage(vec3 world) {
#if ENABLE_SHADOWS == 1 && SIMPLE_DIMENSION == 0
    vec4 projected = shadowProjection * shadowModelView * vec4(world - cameraPosition, 1.0);
    vec3 clip = projected.xyz / projected.w;
    vec3 coordinate = distortShadow(clip) * 0.5 + 0.5;
    if (any(lessThanEqual(coordinate, vec3(0.0))) || any(greaterThanEqual(coordinate, vec3(1.0)))) return 0.0;
    vec2 scale = vec2(shadowProjection[0][0], shadowProjection[1][1]);
    float toBlocks = 2.0 / max(abs(shadowProjection[2][2]), 0.00001);
    float spread = tan(SKY_SUN_RADIUS * CELESTIAL_SIZE);
    float search = clamp(24.0 * spread, 0.15, 3.0);
    float weight = 0.0;
    float blockers = 0.0;
    for (int i = 0; i < 9; ++i) {
        vec2 offset = vec2(i % 3 - 1, i / 3 - 1) * search * 0.66;
        vec2 uv = distortShadow(clip + vec3(offset * scale, 0.0)).xy * 0.5 + 0.5;
        float gap = (coordinate.z - textureLod(shadowtex1, uv, 0.0).r) * toBlocks;
        float w = smoothstep(0.025, 0.09, gap);
        blockers += max(gap, 0.0) * w;
        weight += w;
    }
    // Even with no blockers in the search taps, test the centre neighbourhood;
    // thin leaves can fall between the search locations.
    float radius = clamp(spread * blockers / max(weight, 0.001), 0.045, 3.0);
    float lit = 0.0;
    for (int i = 0; i < 16; ++i) {
        float angle = 2.39996323 * float(i);
        vec2 offset = vec2(cos(angle), sin(angle)) * sqrt((float(i) + 0.5) / 16.0) * radius;
        vec2 uv = distortShadow(clip + vec3(offset * scale, 0.0)).xy * 0.5 + 0.5;
        float gap = (coordinate.z - textureLod(shadowtex1, uv, 0.0).r) * toBlocks;
        lit += 1.0 - smoothstep(0.025, 0.09, gap);
    }
    return lit / 16.0;
#else
    return 1.0;
#endif
}

vec4 waterEntrySample(vec2 pixel) {
    vec2 size = volumeSize();
    float spacing = entryGridSpacing(size);
    vec2 xz = (entryGridOrigin(size, spacing) + pixel) * spacing;
    vec4 history = texelFetch(colortex13, ivec2(0), 0);
    float depth = validWaterMediumHistory(history)
        ? max(history.x + previousCameraPosition.y - cameraPosition.y, 0.0)
        : (1.0 - clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0)) * 15.0;
    vec3 normal = vec3(0.0, 1.0, 0.0);
#if ENABLE_WATER_WAVES == 1
    depth += getWaterWaveHeight(xz, frameTimeCounter);
    normal = getWaterWaveNormal(xz, frameTimeCounter);
#endif
    vec3 direction = refract(-getSunDirWorld(), normal, 1.0 / WATER_IOR);
    vec3 entry = vec3(xz.x, cameraPosition.y + depth, xz.y);
    return vec4(direction.xz, entrySolarCoverage(entry), depth);
}

void main() {
    if (isEyeInWater == 1) {
        vec2 medium = vec2(0.0);
        if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
            medium = estimateWaterMedium(colortex9);
        }
        if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) fullOut0 = vec4(medium, 0.0, 0.0);
        else if (SIMPLE_DIMENSION == 0 && UNDERWATER_SHAFT_STRENGTH > 0.0 && getSunDirWorld().y > 0.0) fullOut0 = waterEntrySample(gl_FragCoord.xy);
        else fullOut0 = vec4(0.0);
        return;
    }
    vec2 size = volumeSize();
    vec2 uv = gl_FragCoord.xy / size;
    float depth = texture(depthtex1, uv).r;
    float limit = depth < 0.999999 ? length(screenToView(uv, depth)) : CLOUD_DISTANCE;
    float waterDepth = readWaterSurface(colortex9, uv).a;
    if (waterDepth > 0.001 && isEyeInWater == 0) {
        vec3 viewRay = screenToView(uv, 0.5);
        limit = min(limit, length(viewRay * waterDepth / max(-viewRay.z, EPSILON)));
    }
    fullOut0 = traceVolumetricClouds(getCloudRayWorld(uv), limit);
}

