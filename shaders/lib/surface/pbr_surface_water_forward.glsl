// Pbr surface for water forward.
#ifndef LIB_PBR_SURFACE_GLSL
#define LIB_PBR_SURFACE_GLSL
/* LabPBR 1.3通用通道解码。不识别方块名称、矿石颜色或特定资源包。
 * specular与normal是线性数据贴图；albedo由调用者预先转为线性颜色。
 */
#include "/lib/labpbr_decode.glsl"

uniform sampler2D normals;
uniform sampler2D specular;

// 高度数据的POM只在有效原生图集范围内步进。平坦高度直接退出，演示包没有额外成本。
#include "/lib/pbr_height.glsl"

vec2 pbrParallaxUv(vec2 uv, vec3 position, vec3 geometric, vec4 tile) {
#if POM_QUALITY == 0
    return uv;
#else
    vec3 dx = dFdx(position);
    vec3 dy = dFdy(position);
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    float determinant = du.x * dv.y - du.y * dv.x;
    vec3 tangent = dx * dv.y - dy * du.y;
    vec3 bitangent = dy * du.x - dx * dv.x;
    if (length(position) > POM_DISTANCE || min(tile.z, tile.w) <= 0.0
        || abs(determinant) < 1e-12 || dot(tangent, tangent) < 1e-16) return uv;
    tangent = normalize(tangent * sign(determinant));
    bitangent = safeNormalize(bitangent * sign(determinant), cross(geometric, tangent));
    vec3 view = safeNormalize(-position, geometric);
    vec3 viewTangent = vec3(dot(view, tangent), dot(view, bitangent), dot(view, geometric));
    return pbrHeightUv(normals, uv, viewTangent, tile, du, dv);
#endif
}

LabPbrMaterial readPbrSurface(vec3 albedo, vec2 uv) {
    vec4 normalMap = texture(normals, uv);
    if (dot(abs(normalMap), vec4(1.0)) < 0.00001) {
        normalMap = vec4(0.5, 0.5, 1.0, 1.0);
    }
    return decodeLabPbr(albedo, texture(specular, uv), normalMap);
}

// Bitangent指向纹理V增大方向，与LabPBR DirectX绿色通道约定一致。
vec3 pbrSurfaceNormal(vec3 geometric, vec3 position, vec2 uv, vec3 tangentNormal) {
    vec3 dx = dFdx(position);
    vec3 dy = dFdy(position);
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    float determinant = du.x * dv.y - du.y * dv.x;
    vec3 tangent = dx * dv.y - dy * du.y;
    vec3 bitangent = dy * du.x - dx * dv.x;
    if (abs(determinant) < 1e-12 || dot(tangent, tangent) < 1e-16) return geometric;
    tangent = normalize(tangent * sign(determinant));
    bitangent = safeNormalize(bitangent * sign(determinant), cross(geometric, tangent));
    return safeNormalize(mat3(tangent, bitangent, geometric) * tangentNormal, geometric);
}

vec3 pbrGlossTangent(vec3 normal, vec3 position, vec2 uv) {
    vec3 tangent = dFdx(position) * dFdy(uv).y - dFdy(position) * dFdx(uv).y;
    vec3 fallback = abs(normal.y) < 0.9 ? cross(normal, vec3(0.0, 1.0, 0.0))
        : cross(normal, vec3(1.0, 0.0, 0.0));
    return safeNormalize(tangent - normal * dot(normal, tangent), normalize(fallback));
}

// 现有原生光源候选与逐灯透射缓存提供局部高光，完全不查询反射场景。
#include "/lib/transparent_pbr.glsl"

vec3 pbrDirectGloss(SurfaceMaterial m, vec3 normal, vec3 position, vec2 uv,
                    vec2 lightmap, vec3 shadow) {
    return transparentDirectGloss(m, normal, position, pbrGlossTangent(normal, position, uv),
        safeNormalize(-position, normal), lightmap, shadow);
}

vec3 computePbrLighting(LabPbrMaterial pbr, vec3 normal, vec2 lightmap, vec3 shadow,
                       float occlusion, vec3 position, vec2 uv, out vec3 reflectionSource) {
    SurfaceMaterial m = pbrBrdfMaterial(pbr);
    float strength = ENABLE_MATERIAL_REFLECTIONS == 1 ? MATERIAL_REFLECTION_STRENGTH : 0.0;
    vec3 view = safeNormalize(-position, normal);
    bool reflective = max(max(m.f0.r, m.f0.g), m.f0.b) > 0.0001 && strength > 0.0;
    vec3 fraction = vec3(1.0);
    if (reflective) {
        // 偏漫反射的Glossy风格为粗糙金属保留少量基底散射。
        fraction = mix(vec3(1.0), (1.0 - 0.85 * m.metallic)
            * (1.0 - materialFresnel(m.f0, dot(normal, view))), strength);
    }
    vec3 diffuse = computeSurfaceLighting(pbr.albedo * fraction, normal, lightmap, shadow,
        occlusion * pbr.ao, position);
    vec3 environment = vec3(0.0);
    vec3 direct = vec3(0.0);
    if (reflective) {
        vec3 direction = normalize(mat3(gbufferModelViewInverse) * normal);
        environment = materialAmbientEnvironment(direction, lightmap)
            * materialEnvironmentWeight(m, dot(normal, view)) * strength;
        direct = pbrDirectGloss(m, normal, position, uv, lightmap, shadow) * strength;
    }
    vec3 emission = pbr.albedo * pbr.emission * ORE_GLOW_STRENGTH * 4.0;
    reflectionSource = diffuse + environment + emission;
    return reflectionSource + direct;
}
#endif
