#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;
layout(location=5) out vec4 fullOut5;
/* Supply the sky before translucent blending, and preserve opaque HDR for water. */
/* RENDERTARGETS: 6,0,1,2,15 */
uniform sampler2D colortex1;
/* The entire uncovered background shares one atmosphere and celestial model. */
#include "/lib/atmosphere/sky_background_deferred_surface.glsl"

/* 资源包驱动的通用不透明表面。材质贴图保持线性数据，颜色由调用者转为线性空间。 */
#include "/lib/surface/pbr_surface_forward.glsl"

/*
 * Single-scattering volumetric cloud integration with approximate multiple
 * scattering. Main sky clouds render at half resolution; reflections use fewer
 * samples. Empty regions skip lighting and dense rays terminate early. A finite
 * cylindrical horizon bounds grazing rays before any density/noise sampling.
 */
#include "/lib/atmosphere/clouds_deferred_surface.glsl"

/* 雨后地表薄水层。湿度控制积累与消退，连续噪声给出局部积水分布。
 * 法线、原生天光和已有地表高度共同限制范围，避免墙面、树叶与屋内地板积水。
 * 不改变世界几何；水膜使用粗糙光泽、局部高光与雨滴波环。
 */
#include "/lib/core/wet_surface.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;
#if ENABLE_MATERIAL_REFLECTIONS == 1
const bool colortex0MipmapEnabled = false;
#endif

uniform sampler2D colortex15;
uniform sampler2D depthtex2;

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float depth = texture(depthtex0, uv).r;
    vec4 opaque = texture(colortex0, uv);
    // Source alpha packs coverage (bit 0) and cutout class (bit 1). It is not
    // a blend opacity: a leaf hole containing a wall keeps the wall's coverage.
    float cutout = abs(texture(colortex1, uv).a - MAT_FOLIAGE) < 0.025 ? 2.0 : 0.0;
    // Preserve the existing opaque/cutout bands. Their fraction carries the
    // terrain plane for water intersections. Other draw types have no tag.
    bool aquatic = opaque.a >= 16.0 && opaque.a <= 22.0;
    bool rasterCutout = opaque.a >= 24.0 && opaque.a <= 30.0;
    float faceTag = rasterCutout ? opaque.a - 16.0 : (aquatic ? opaque.a - 8.0 : opaque.a);
    float face = faceTag >= 9.0 && faceTag <= 14.0 ? round(faceTag - 8.0) : 0.0;
    if (rasterCutout) cutout = 2.0;
    if (aquatic) cutout = 4.0;
    int crease = 0;
    if (face > 0.0) {
        ivec2 pixel = ivec2(gl_FragCoord.xy);
        ivec2 last = textureSize(colortex0, 0) - 1;
        const ivec2 offsets[4] = ivec2[4](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));
        for (int i = 0; i < 4; ++i) {
            float other = texelFetch(colortex0, clamp(pixel + offsets[i], ivec2(0), last), 0).a;
            if (other >= 9.0 && other <= 14.0 && other != opaque.a) crease |= 1 << i;
        }
    }
    vec4 reflectionSource = depth < 0.999999
        ? vec4(opaque.rgb, 1.0 + cutout + (face * 16.0 + float(crease)) / 256.0) : vec4(0.0);
    // Preserve the exact view-facing plane of native sprites. Sparse depth
    // neighbours around a particle do not describe its raster plane.
    bool billboard = abs(texture(colortex1, uv).a - MAT_BILLBOARD) < 0.002;
    if (billboard && depth < 0.999999) reflectionSource.a = 1.5;
    vec3 color = fillSkyBackground(opaque.rgb, uv, depth);
    // 方块只保留漫反射/粗糙Glossy，场景辐射仍单独发布给水面使用。
    bool wetActive = ENABLE_RAIN_PUDDLES == 1 && weatherGroundWetness() * RAIN_PUDDLES_STRENGTH > 0.001;
    vec3 relative = vec3(0.0);
    float footprint = 0.0;
    if (wetActive) {
        relative = viewToWorld(screenToView(uv, min(depth, 0.99999)));
        footprint = max(length(dFdx(relative.xz)), length(dFdy(relative.xz)));
    }
    if (wetActive && depth < 0.999999) {
        vec4 geometry = texture(colortex1, uv);
        if (abs(geometry.a - MAT_WET_GROUND) < 0.025) {
            vec3 normal = decodeNormal(geometry.rg);
            vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normal);
            vec4 physical = texture(colortex14, uv);
            float metallic = texture(colortex2, uv).a;
            vec2 wet = wetGroundCoverage(relative, worldNormal, geometry.b, metallic, footprint);
            color *= 1.0 - wet.x * 0.12 - wet.y * 0.18;
            if (wet.y > 0.015) {
                vec3 position = screenToView(uv, depth);
                vec3 view = normalize(-position);
                vec2 lightmap = texture(colortex2, uv).rg;
                SurfaceMaterial original;
                original.f0 = physical.rgb;
                original.roughness = max(physical.a, MATERIAL_GLOSS_ROUGHNESS);
                original.metallic = metallic;
                vec3 oldEnvironment = materialAmbientEnvironment(worldNormal, lightmap)
                    * materialEnvironmentWeight(original, dot(normal, view)) * MATERIAL_REFLECTION_STRENGTH;
                SurfaceMaterial coating;
                coating.f0 = vec3(0.025);
                coating.roughness = max(0.35, MATERIAL_GLOSS_ROUGHNESS);
                coating.metallic = 0.0;
                vec3 wetNormal = wetSurfaceNormal(normal, relative, wet.y, footprint);
                vec3 wetWorld = normalize(mat3(gbufferModelViewInverse) * wetNormal);
                vec3 environment = materialAmbientEnvironment(wetWorld, lightmap)
                    * materialEnvironmentWeight(coating, dot(wetNormal, view));
                vec3 tangent = mat3(gbufferModelView) * vec3(1.0, 0.0, 0.0);
                vec3 direct = materialDirectSpecular(coating, wetNormal, position, lightmap, vec3(1.0))
                    + pbrLocalGloss(coating, wetNormal, tangent, position, 0.0);
                color = max(color + (environment - oldEnvironment + direct) * wet.y
                    * (1.0 - getFogFactor(length(position))), vec3(0.0));
            }
        }
    }
    // Glass writes depth. Filling its background afterwards would leave black
    // behind every nonzero-alpha texel, even though clear glass holes look fine.
    fullOut1 = vec4(color, 1.0);
    // Sheet transmission needs radiance even where no opaque receiver exists.
    // Keep alpha zero for sky so geometric traces continue to reject it.
    if (depth >= 0.999999) reflectionSource.rgb = color;
    // Opaque hands have already rendered on some loader paths. Retain the
    // independently captured colour and depth at those pixels; only fill sky.
    float preHandDepth = texelFetch(depthtex2, ivec2(gl_FragCoord.xy), 0).r;
    vec3 preHandColour = depth == preHandDepth ? color
        : fillSkyBackground(texelFetch(colortex15, ivec2(gl_FragCoord.xy), 0).rgb, uv, preHandDepth);
    fullOut4 = vec4(preHandColour, 1.0);
    // 雾色差留到透明物与天气混合后统一修正，避免与 composite2 重复着色。
    // 常规路径的反射源已包含相机雾；同步其天空色，避免雨天倒影保留旧蓝雾。
    // 主画面仍在透明物与雨层合成后独立修正，不重复修改显示颜色。
    if (depth < 0.999999) {
        reflectionSource.rgb = correctSkyFog(reflectionSource.rgb, uv,
            length(screenToView(uv, depth)), 1.0);
    }
    fullOut0 = reflectionSource;
#if DEBUG_VIEW == 0
    // 反射已读完不透明 G-Buffer，清出水面参数与独立透明层的存储位置。
    fullOut2 = vec4(0.0);
    fullOut3 = vec4(0.0);
#else
    fullOut2 = texture(colortex1, uv);
    fullOut3 = texture(colortex2, uv);
#endif
}

