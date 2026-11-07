#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* deferred.fsh: build the sky-view LUT, the cloud environment LUT above it
 * and the adjacent world-space cloud shadow cache. */
/* RENDERTARGETS: 3 */
/* Sky lookup, circular celestial bodies and a continuous stellar background. */
#include "/lib/atmosphere/sky_deferred_surface.glsl"

/* 日光体积阴影缓存。固定高度层积分云消光，世界坐标网格随相机平移时按格移动。
 * 缓存位于天空 LUT 右侧的 alpha 区域，沿光线投影后可查询任意近地面体积点。
 */
#include "/lib/lighting/air_shadow_deferred_ambient.glsl"

/*
 * Single-scattering volumetric cloud integration with approximate multiple
 * scattering. Main sky clouds render at half resolution; reflections use fewer
 * samples. Empty regions skip lighting and dense rays terminate early. A finite
 * cylindrical horizon bounds grazing rays before any density/noise sampling.
 */
#include "/lib/atmosphere/clouds_deferred_ambient.glsl"

// 与天空 LUT 同一映射；水面反射和水下出射只需查表，不再逐像素步进体积云。
vec4 buildCloudEnvironment(vec2 texel, vec2 size) {
    vec2 coordinate = vec2(texel.x / size.x, (texel.y - size.y - 0.5) / max(size.y - 1.0, 1.0));
    vec3 direction = skyLookupDirection(coordinate);
    if (direction.y <= CLOUD_MIN_DIRECTION_Y) {
        return vec4(0.0);
    }
    // 相机在云层之上时仍从云底以下观察，与水面所见一致。
    vec3 origin = cameraPosition;
    origin.y = min(origin.y, cloudAltitudeBounds().x - 1.0);
    return traceVolumetricCloudsLit(origin, direction, CLOUD_DISTANCE, false,
                                    integrateAtmosphere(direction));
}

void main() {
    vec2 size = max(floor(vec2(viewWidth, viewHeight) * 0.125), vec2(1.0));
    if (gl_FragCoord.x >= size.x || gl_FragCoord.y >= size.y) {
        if (gl_FragCoord.x < size.x && gl_FragCoord.y < size.y * 2.0) {
            fullOut0 = buildCloudEnvironment(gl_FragCoord.xy, size);
            return;
        }
        float shadow = 1.0;
        if (gl_FragCoord.x >= size.x && gl_FragCoord.x < size.x * 2.0
            && gl_FragCoord.y < size.y && isEyeInWater == 0) {
            vec2 uv = (gl_FragCoord.xy - vec2(size.x, 0.0)) / size;
            shadow = buildAirCloudShadow(uv, skySunDirection());
        }
        fullOut0 = vec4(0.0, 0.0, 0.0, shadow);
        return;
    }
    vec2 coordinate = gl_FragCoord.xy / size;
    // 极点本身必须有一整行相同的辐射值，避免经线在中心收敛成亮点。
    coordinate.y = (gl_FragCoord.y - 0.5) / max(size.y - 1.0, 1.0);
    if (coordinate.y <= 0.0) {
        // 下极点没有方位角，用四个地平线方向的平均值作为统一边界。
        const float diagonal = 0.70710678;
        vec3 pole = integrateAtmosphere(vec3(diagonal, -diagonal, 0.0));
        pole += integrateAtmosphere(vec3(-diagonal, -diagonal, 0.0));
        pole += integrateAtmosphere(vec3(0.0, -diagonal, diagonal));
        pole += integrateAtmosphere(vec3(0.0, -diagonal, -diagonal));
        fullOut0 = vec4(pole * 0.25, 1.0);
        return;
    }
    fullOut0 = vec4(integrateAtmosphere(skyLookupDirection(coordinate)), 1.0);
}

