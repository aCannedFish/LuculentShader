#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
/* 半分辨率体积场。空气中将近地面日光散射置于云层之前；水下 RGB 保存光柱，
 * alpha 保存路径深度，首个 alpha 保留每帧一次的入水深度估计。
 */
/* RENDERTARGETS: 4 */
/* 柔和聚光与水下日照工具。变形胞元模拟聚光纹理，太阳折射方向决定投影；
 * 仅查询现有的不透明阴影图，不生成光子、光照贴图或额外场景数据。
 */
#include "/lib/water/water_effects_volume_water.glsl"

/* Shared viewport shape for clouds, air scattering and underwater shafts.
 * Buffers keep full attachment sizes; generation and reconstruction must agree
 * on the active lower-left region, including odd internal render dimensions.
 */
#include "/lib/atmosphere/volume_resolution.glsl"

uniform sampler2D colortex3;
/* Near-scene media share the existing reduced-resolution volume attachment.
 * Terrain mist is depth-clipped and visibility-bounded; dimension haze reuses
 * the companion's diffuse SH field for soft local glow. Optical-depth blending
 * avoids adding two independent full-strength veils in overlapping air.
 */
#include "/lib/atmosphere/atmosphere_media_volume_water.glsl"

uniform sampler2D colortex9;
uniform sampler2D colortex1;
uniform sampler2D depthtex1;
SIMPLE_VARYING float vAirDensityModulation;

void main() {
    vec2 size = volumeSize();
    vec2 uv = gl_FragCoord.xy / size;
    if (isEyeInWater != 1) {
        vec4 cloud = texture(colortex4, uv * size / vec2(viewWidth, viewHeight));
        float depth = texture(depthtex1, uv).r;
        float distance = depth < 0.999999 ? length(screenToView(uv, depth)) : far;
        float waterDepth = readWaterSurface(colortex9, uv).a;
        if (waterDepth > 0.001) {
            distance = min(distance, length(waterSurfacePosition(uv, waterDepth)));
        }
        vec4 air = integrateAirScattering(uv, distance, vAirDensityModulation);
        air = mergeAtmosphericMedia(air, integrateLocalAtmosphere(uv, distance));
        // 近地面介质位于云层之前，按透射率组合，避免重复叠加亮度。
        fullOut0 = vec4(air.rgb + cloud.rgb * (1.0 - air.a),
                              1.0 - (1.0 - air.a) * (1.0 - cloud.a));
        return;
    }
    vec2 medium = texture(colortex4, vec2(0.5) / vec2(viewWidth, viewHeight)).rg;
    if (gl_FragCoord.x < 1.0 && gl_FragCoord.y < 1.0) {
        fullOut0 = vec4(medium.y, 0.0, 0.0, medium.x);
        return;
    }
    float eyeDepth = medium.x;
    float opaqueDepth = texture(depthtex1, uv).r;
    float surfaceDepth = readWaterSurface(colortex9, uv).a;
    float path = underwaterVisiblePath(uv, opaqueDepth, surfaceDepth, eyeDepth);
    vec3 shafts = integrateWaterShafts(uv, path, eyeDepth, medium.y);
    float metadata = min(path, 48.0);
    fullOut0 = vec4(shafts, metadata);
}

