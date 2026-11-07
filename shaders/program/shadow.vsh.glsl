// The geometry stage passes these values through after recording complete
// transparent triangles. Fragment-stage names remain unchanged.
#define vTexCoord gTexCoord
#define vColor gColor
#define vShadowPosition gShadowPosition
#define vCasterNormal gCasterNormal
#define vCasterLight gCasterLight
#define vWaterFaceParity gWaterFaceParity
#define vCaster gCaster

/* Shadow vertices atomically publish a compact material per block. Priority is
 * deterministic: emitters, opaque geometry, then transmission. The second
 * fixed-size C5 image is detached from all raster attachments. Native shadow
 * drawing therefore cannot overwrite it, and front-end water data uses C9.
 */
#ifndef SIMPLE_CONVENTIONAL_VOXEL_GLSL
#define SIMPLE_CONVENTIONAL_VOXEL_GLSL
/* Compact local lighting. Fixed-size C5 is an image-only integer voxel store,
 * C10 holds three source identities, C11 their cached RGB transmission,
 * and C8 low-energy diffuse radiance. Direct RGB contributions remain separate
 * until the material consumer adds their independently shadowed radiance.
 */
#ifndef SIMPLE_CONVENTIONAL_LPV_GLSL
#define SIMPLE_CONVENTIONAL_LPV_GLSL
/* 全局渲染设置。集中定义加载器常量、缓冲格式和可调宏；各程序共享同一组默认值。
 * 游戏内选项由 shaders.properties 分组，用户选择由加载器保存。
 */
#include "/settings.glsl"

/* 加载器输入声明。集中定义相机、时间、天气、光照、深度与视图/阴影矩阵 uniform。
 */
#include "/lib/uniforms.glsl"

#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
uniform sampler2D colortex8;
// J9 restores every shadow draw attachment during native terrain submission.
// Fixed-size C5 is detached from the scene FBO and cannot be overwritten by
// raster outputs. Image reads also avoid J9's forced LINEAR sampler filtering.
uniform sampler2D colortex10;
uniform sampler2D colortex11;
const int LPV_HEADER_SIZE = 2;
const uint LPV_GLASS = 1u;
const uint LPV_SOLID = 2u;
const uint LPV_EMITTER = 3u;

ivec3 lpvShape() {
    return ivec3(COLOURED_VOLUME_SIZE, COLOURED_VOLUME_SIZE / 2, COLOURED_VOLUME_SIZE);
}

ivec3 lpvOrigin(vec3 camera) {
    return ivec3(floor(camera)) - lpvShape() / 2;
}

bool lpvInside(ivec3 cell) {
    return all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, lpvShape()));
}

int lpvIndex(ivec3 cell) {
    ivec3 shape = lpvShape();
    return cell.x + shape.x * (cell.y + shape.y * cell.z);
}

ivec3 lpvCell(int index) {
    ivec3 shape = lpvShape();
    return ivec3(index % shape.x, (index / shape.x) % shape.y, index / (shape.x * shape.y));
}

ivec2 lpvAddress(ivec3 cell) {
    int address = lpvIndex(cell) + LPV_HEADER_SIZE;
    int width = textureSize(colortex8, 0).x;
    return ivec2(address % width, address / width);
}

uint lpvVoxel(ivec3 cell) {
    if (!lpvInside(cell)) return 0u;
    int index = lpvIndex(cell);
    int width = imageSize(colorimg5).x;
    return imageLoad(colorimg5, ivec2(index % width, index / width)).r;
}

// 后半段保存原生顶点的几何投票：0未知、1只有完整方块角点、2出现内部顶点。
// 仅辅助隐藏反射面的置信度，不以整格几何替代原生反射表面。
bool lpvFullCubeGeometry(ivec3 cell) {
    if (!lpvInside(cell)) return false;
    ivec3 shape = lpvShape();
    int index = lpvIndex(cell) + shape.x * shape.y * shape.z;
    int width = imageSize(colorimg5).x;
    return imageLoad(colorimg5, ivec2(index % width, index / width)).r == 1u;
}

uint lpvKind(uint material) {
    return material >> 30u;
}

vec3 lpvColour(uint material) {
    return vec3(material & 255u, (material >> 8u) & 255u,
        (material >> 16u) & 255u) / 255.0;
}

float lpvEmission(uint material) {
    return float((material >> 24u) & 15u);
}

bool lpvOpaque(uint material) {
    return lpvKind(material) == LPV_SOLID
        || (lpvKind(material) == LPV_EMITTER && (material & (1u << 28u)) != 0u);
}

int lpvHeaderFrame(vec4 header) {
    return int(round(header.y)) + int(round(header.z)) * 1024;
}

// History carries its own origin. Rebase cells and source IDs together, rejecting
// reloads, resizes, teleports and floating-origin jumps before reading old data.
bool lpvHeaderValid(vec4 header) {
    int delta = (frameCounter - lpvHeaderFrame(header) + 720720) % 720720;
    vec4 sourceHeader = texelFetch(colortex10, ivec2(0), 0);
    ivec3 oldOrigin = ivec3(round(texelFetch(colortex10, ivec2(1, 0), 0).xyz));
    return header.w == 1961.0 && int(round(header.x)) == lpvShape().x && delta <= 1
        && all(equal(header, sourceHeader))
        && all(lessThanEqual(abs(lpvOrigin(cameraPosition) - oldOrigin), lpvShape() / 2));
}

vec3 lpvReadCell(ivec3 cell) {
    if (!lpvInside(cell)) return vec3(0.0);
    return max(texelFetch(colortex8, lpvAddress(cell), 0).rgb, vec3(0.0));
}

vec3 lpvSample(vec3 world) {
    if (!lpvHeaderValid(texelFetch(colortex8, ivec2(0), 0))) return vec3(0.0);
    vec3 position = world - vec3(lpvOrigin(cameraPosition)) - 0.5;
    ivec3 first = ivec3(floor(position));
    vec3 weight = fract(position);
    vec3 result = vec3(0.0);
    for (int corner = 0; corner < 8; corner++) {
        ivec3 offset = ivec3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1);
        vec3 blend = mix(1.0 - weight, weight, vec3(offset));
        result += lpvReadCell(first + offset) * blend.x * blend.y * blend.z;
    }
    return result;
}

// Smooth finite-range attenuation depends on each emitter's own level. A nearby
// lamp cannot extend another colour's range by raising the native maximum level.
float lpvSourceEnergy(float distance, float emission) {
    float fraction = clamp(distance / max(emission, 1.0), 0.0, 1.0);
    float cutoff = 1.0 - fraction * fraction * fraction * fraction;
    return 4.0 * BLOCK_LIGHT_STRENGTH * emission / 15.0 * cutoff * cutoff
        / (1.0 + (BLOCK_LIGHT_FALLOFF / 6.0) * (distance + 2.0) * (distance + 2.0));
}

// Shared current occupancy supplies independent source visibility. Advance all
// tied axes so a corner-only contact cannot intermittently occlude a light.
vec3 lpvVisibility(vec3 receiver, ivec3 source) {
    vec3 endpoint = vec3(source) + vec3(0.5, 0.72, 0.5);
    vec3 delta = endpoint - receiver;
    ivec3 cell = ivec3(floor(receiver));
    ivec3 direction = ivec3(sign(delta));
    vec3 inverse = 1.0 / max(abs(delta), vec3(0.00001));
    vec3 boundary = vec3(cell) + step(vec3(0.0), delta);
    vec3 next = abs(boundary - receiver) * inverse;
    next = mix(vec3(1e20), next, notEqual(direction, ivec3(0)));
    vec3 transfer = vec3(1.0);
    for (int stepIndex = 0; stepIndex < 48; stepIndex++) {
        if (all(equal(cell, source))) return transfer;
        if (!lpvInside(cell)) return vec3(0.0);
        uint voxel = lpvVoxel(cell);
        if (lpvOpaque(voxel)) return vec3(0.0);
        if (lpvKind(voxel) == LPV_GLASS) transfer *= lpvColour(voxel);
        float crossing = min(next.x, min(next.y, next.z));
        if (crossing > 1.0) return transfer;
        bvec3 advance = lessThanEqual(next, vec3(crossing + 0.000001));
        cell += direction * ivec3(advance);
        next += inverse * vec3(advance);
    }
    return vec3(0.0);
}

// Blend candidate support over four cells in the receiving surface plane.
// A third source leaving one cell fades into the neighbour's third source;
// changing a discrete top-three list cannot instantly replace its colour.
// Additive light commutes with interpolation. Accumulate each cell directly to
// avoid dynamically indexed candidate arrays and per-pixel identity searches.
vec3 lpvSurfaceDirect(vec3 receiver, vec3 normal, out float explained) {
    vec3 direct = vec3(0.0);
    explained = 0.0;
    vec3 axis = abs(normal);
    vec3 plane = axis.x >= axis.y && axis.x >= axis.z ? vec3(0.0, 1.0, 1.0)
        : axis.y >= axis.z ? vec3(1.0, 0.0, 1.0) : vec3(1.0, 1.0, 0.0);
    vec3 first = plane.x > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 second = plane.z > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 shifted = receiver - 0.5 * plane;
    ivec3 base = ivec3(floor(shifted));
    vec2 fraction = vec2(dot(fract(shifted), first), dot(fract(shifted), second));
    for (int x = 0; x < 2; x++) {
        for (int y = 0; y < 2; y++) {
            ivec3 cell = base + ivec3(first) * x + ivec3(second) * y;
            if (!lpvInside(cell)) continue;
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                * (y == 0 ? 1.0 - fraction.y : fraction.y);
            if (weight <= 0.0) continue;
            ivec2 address = lpvAddress(cell);
            vec3 stored = texelFetch(colortex10, address, 0).rgb;
            float strongest = 0.0;
            for (int entry = 0; entry < 3; entry++) {
                int identity = int(round(stored[entry])) - 1;
                if (identity < 0) continue;
                ivec3 source = lpvCell(identity);
                uint material = lpvVoxel(source);
                if (lpvKind(material) != LPV_EMITTER) continue;
                vec3 ray = vec3(source) + vec3(0.5, 0.72, 0.5) - receiver;
                float distance = length(ray);
                float energy = lpvSourceEnergy(distance, lpvEmission(material));
                strongest = max(strongest, energy);
                float diffuse = 0.35 + 0.65 * max(dot(normal, ray / max(distance, 0.00001)), 0.0);
                vec3 colour = lpvColour(material);
                ivec2 cached = address + ivec2(0, entry * textureSize(colortex8, 0).y);
                vec3 transmission = texelFetch(colortex11, cached, 0).rgb;
                direct += colour * colour * energy * diffuse * transmission * weight;
            }
            explained += strongest * weight;
        }
    }
    return direct;
}

vec3 lpvBlockLight(vec3 viewPosition, vec3 normalView, vec3 nativeRadiance) {
    if (nativeRadiance.r <= 0.000001 || COLOURED_LIGHT_INTENSITY <= 0.0
        || !lpvHeaderValid(texelFetch(colortex8, ivec2(0), 0))) return nativeRadiance;
    vec3 normal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 world = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz + cameraPosition;
    vec3 receiver = world + normal * 0.04 - vec3(lpvOrigin(cameraPosition));
    ivec3 cell = ivec3(floor(receiver));
    if (!lpvInside(cell)) return nativeRadiance;
    float explained;
    vec3 direct = lpvSurfaceDirect(receiver, normal, explained);
    // Storage follows integer blocks, but coverage follows the interpolated
    // camera. Advancing the storage origin must not jump the blend weight.
    // A one-block guard keeps the continuous fade inside both integer grids.
    vec3 relative = world + normal * 0.04 - cameraPosition;
    vec3 border = vec3(lpvShape()) * 0.5 - abs(relative);
    float coverage = smoothstep(1.0, 5.0, min(border.x, min(border.y, border.z)));
    float replaced = clamp(explained / max(nativeRadiance.r, 0.00001), 0.0, 1.0);
    vec3 indirect = vec3(0.0);
#if GI_QUALITY == 0
    indirect = lpvSample(world + normal * 0.7) * (0.16 * BLOCK_LIGHT_STRENGTH);
#endif
    vec3 local = nativeRadiance * (1.0 - replaced) + direct + indirect;
    return mix(nativeRadiance, local, coverage * COLOURED_LIGHT_INTENSITY);
}
#endif
#endif

#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
// 任一原生模型顶点不在立方体角点时，整格遮挡证据即失效；partial投票优先。
// 使用实际几何属性，资源包改变模型后无需按方块名称维护分类表。
void lpvCaptureGeometry(vec3 centre, vec3 midBlock) {
    if (!isTerrainStage()) return;
    ivec3 cell = ivec3(floor(centre + 0.001)) - lpvOrigin(cameraPosition);
    if (!lpvInside(cell)) return;
    bool corner = all(lessThan(abs(abs(midBlock) - vec3(32.0)), vec3(0.1)));
    ivec3 shape = lpvShape();
    int index = lpvIndex(cell) + shape.x * shape.y * shape.z;
    int width = imageSize(colorimg5).x;
    imageAtomicMax(colorimg5, ivec2(index % width, index / width), corner ? 1u : 2u);
}

uint lpvPackMaterial(vec3 colour, uint kind, int emission, bool solid) {
    uvec3 rgb = uvec3(round(clamp(colour, 0.0, 1.0) * 255.0));
    return (kind << 30u) | (uint(emission) << 24u) | (uint(solid) << 28u)
        | rgb.r | (rgb.g << 8u) | (rgb.b << 16u);
}

uint lpvVoxelMaterial(int id) {
    if (id == 6000) return lpvPackMaterial(vec3(1.0, 0.46, 0.12), LPV_EMITTER, 15, true);
    if (id == 6001) return lpvPackMaterial(vec3(0.10, 0.65, 1.0), LPV_EMITTER, 10, false);
    if (id == 6002) return lpvPackMaterial(vec3(1.0, 0.05, 0.01), LPV_EMITTER, 7, false);
    if (id == 6003) return lpvPackMaterial(vec3(0.55, 0.95, 0.82), LPV_EMITTER, 15, true);
    if (id == 6004) return lpvPackMaterial(vec3(0.92, 0.85, 1.0), LPV_EMITTER, 14, false);
    if (id == 6005) return lpvPackMaterial(vec3(0.48, 1.0, 0.35), LPV_EMITTER, 15, true);
    if (id == 6006) return lpvPackMaterial(vec3(1.0, 0.58, 0.90), LPV_EMITTER, 15, true);
    if (id == 6007) return lpvPackMaterial(vec3(0.68, 0.20, 1.0), LPV_EMITTER, 10, true);
    if (id == 6008) return lpvPackMaterial(vec3(1.0, 0.35, 0.08), LPV_EMITTER, 15, true);
    if (id == 6009) return lpvPackMaterial(vec3(0.68, 0.20, 1.0), LPV_EMITTER, 5, false);
    if (id == 6010 || id == 101) return lpvPackMaterial(vec3(1.0, 0.46, 0.12), LPV_EMITTER, 14, false);
    if (id == 102) return lpvPackMaterial(vec3(0.85, 0.80, 1.0), LPV_EMITTER, 14, false);
    if (id == 100 || id == 110) return lpvPackMaterial(vec3(0.90, 0.95, 1.0), LPV_GLASS, 0, false);
    if (id >= 200 && id < 300) return lpvPackMaterial(vec3(0.85, 0.95, 0.75), LPV_GLASS, 0, false);
    return lpvPackMaterial(vec3(0.0), LPV_SOLID, 0, true);
}

void lpvCaptureVertex(vec3 centre, int id) {
    // J9 interleaves ENTITIES=10, BLOCK_ENTITIES=11 and HAND_SOLID=15 between
    // terrain passes. Their vertices do not carry a valid terrain at_midBlock
    // or material attribute; accepting them creates moving solid/emitter cells.
    if (!isTerrainStage()) return;
    ivec3 cell = ivec3(floor(centre + 0.001)) - lpvOrigin(cameraPosition);
    if (!lpvInside(cell)) return;
    int index = lpvIndex(cell);
    ivec2 size = imageSize(colorimg5);
    imageAtomicMax(colorimg5, ivec2(index % size.x, index / size.x), lpvVoxelMaterial(id));
}

// Diffuse GI needs the terrain's linear albedo and native skylight. The four
// emission bits are unused for ordinary solids and hold their sky level instead.
// Quantized atlas colours avoid texture-edge and vertex-order noise in the field.
void lpvCaptureSurface(vec3 centre, int id, vec3 albedo, float skyLevel) {
    if (!isTerrainStage()) return;
    ivec3 cell = ivec3(floor(centre + 0.001)) - lpvOrigin(cameraPosition);
    if (!lpvInside(cell)) return;
    uint material = lpvVoxelMaterial(id);
    if (lpvKind(material) == LPV_SOLID) {
        vec3 diffuse = floor(clamp(albedo, 0.0, 0.85) * 31.0 + 0.5) / 31.0;
        material = lpvPackMaterial(diffuse, LPV_SOLID, int(round(skyLevel * 15.0)), true);
    }
    int index = lpvIndex(cell);
    int width = imageSize(colorimg5).x;
    imageAtomicMax(colorimg5, ivec2(index % width, index / width), material);
}
#endif
#endif

uniform sampler2D gtexture;
in vec2 mc_midTexCoord;
#define SIMPLE_VARYING out

in vec3 vaPosition;
in vec4 vaColor;
in vec3 vaNormal;
in vec2 vaUV0;
in ivec2 vaUV2;
#include "/lib/core/vertex_input.glsl"
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
in vec3 mc_Entity;

/*
================================================================================
 shadow.vsh —— 阴影贴图顶点着色器
================================================================================
 这个程序【不渲染任何颜色】，它只做一件事：
 站在太阳的位置，把整个世界的深度信息烤进一张贴图。

 渲染过程：
   1. OptiFine 把场景里所有会投影的几何体重新送一遍进来；
   2. modelViewMatrix 把当前区块/实体从模型空间转到阴影视图空间，
      projectionMatrix 再投影；
   3. 施加和 gbuffers 完全一样的畸变；
   4. GPU 自动把深度写进 shadowMap。

 和 gbuffers_terrain.vsh 对照着看会发现：公式一模一样，
 只是把 gbufferModelView/gbufferProjection 换成了 shadow 系列。
 这正是"阴影贴图 = 从光源视角再渲染一遍"的字面含义。

 注意这里【没有】gbufferModelViewInverse：阴影绘制时的内置矩阵
 已经包含了当前几何体的变换，无须重新还原玩家视图空间坐标。

 调试技巧：把 settings.glsl 里 shadowDistance 调小到 32，
 就能在游戏里看清阴影贴图的覆盖范围 —— 超出范围的地方没有阴影。
================================================================================
*/

/* 全局渲染设置。集中定义加载器常量、缓冲格式和可调宏；各程序共享同一组默认值。
 * 游戏内选项由 shaders.properties 分组，用户选择由加载器保存。
 */
#include "/settings.glsl"

/* 加载器输入声明。集中定义相机、时间、天气、光照、深度与视图/阴影矩阵 uniform。
 */
#include "/lib/uniforms.glsl"

/*
================================================================================
 lib/common.glsl —— 通用常量与数学工具
================================================================================
 这里只放"纯函数"：不声明 uniform、不声明 SIMPLE_VARYING、不读写纹理。
 因此这个文件可以被顶点着色器和片元着色器同时安全地 include。

 命名约定（整个项目统一遵守）：
   - 变量、函数：lowerCamelCase
   - 宏（#define）：UPPER_SNAKE_CASE
   - 顶点属性：GLSL 120 兼容程序使用 gl_* 内置属性
   - uniform：不加前缀，直接用 OptiFine 提供的名字
   - SIMPLE_VARYING：v 开头
   - 材质/枚举：MAT_ 开头
================================================================================
*/
#include "/lib/core/common.glsl"

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_forward.glsl"

/*
 * 植被顶点风摆。地形和阴影共用世界坐标、时间、分类与位移函数。
 * 叶片采用连续空间场以保持相邻方块接缝；草/花/作物以根部为固定支点。
 * 两格植物的上下部分使用同一根部、相位和高度曲线。
 */
#include "/lib/core/foliage_wind.glsl"

// 植被只对已映射的方块生效，实体和普通方块保留原来的位置。

in vec3 at_midBlock;

SIMPLE_VARYING vec2 vTexCoord;
SIMPLE_VARYING vec4 vColor;
SIMPLE_VARYING vec3 vShadowPosition;
// Surface orientation and light levels belong to the same native alpha-tested texel.
SIMPLE_VARYING vec3 vCasterNormal;
SIMPLE_VARYING vec2 vCasterLight;
flat SIMPLE_VARYING int vWaterFaceParity;
// 投影体类别：0 不透明，1 发光方块，2 透光玻璃，3 水，4 薄植被。
SIMPLE_VARYING float vCaster;
SIMPLE_VARYING vec3 gNativePosition;
flat SIMPLE_VARYING int gTransparentTriangle;

uniform vec4 spriteBounds;
#include "/lib/water_face_cache.glsl"

// Each corner carries its active atlas UV, tint, AO and light levels.
// Transparent terrain has its own class and can never supply an opaque hit.
void waterCaptureFace(vec3 centre, vec3 normal, bool glass) {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (!isOpaqueTerrainStage() && !glass) return;
    // Far bank fronts and overhangs remain useful even to a nearby mirror.
    // Reserve sparse slots by omitting far wall backs and upward faces above
    // the eye, which an ascending reflected ray from below cannot enter.
    vec3 toEye = cameraPosition - centre;
    if (isEyeInWater == 0 && dot(toEye, toEye) > 32.0 * 32.0) {
        if (abs(normal.y) < 0.01 && dot(normal, toEye) < -6.0) return;
        if (normal.y > 0.99 && toEye.y < -2.0) return;
    }
    ivec3 owner = ivec3(floor(centre));
    ivec3 cell = owner - waterFarOrigin();
    if (!waterFarInside(cell)) return;
    vec3 n = abs(normal);
    int axis = n.x > max(n.y, n.z) ? 0 : (n.y > n.z ? 1 : 2);
    if (n[axis] < 0.9999) return;
    vec3 offset = -at_midBlock / 64.0;
    if (abs(offset[axis] - sign(normal[axis]) * 0.5) > 0.001) return;
    vec2 local = waterFaceAxes(offset, axis);
    int face = waterFindFace(owner, axis, normal[axis] < 0.0, true, glass);
    if (face < 0) return;
    if (any(greaterThan(abs(abs(local) - 0.5), vec2(0.001)))) {
        imageAtomicOr(colorimg5, waterFaceAddress(face, 2), 16u);
        imageAtomicOr(colorimg5, waterFaceAddress(face, 3), 16u);
        return;
    }
    int corner = int(local.x > 0.0) + 2 * int(local.y > 0.0);
    vec2 extent = spriteBounds.zw - spriteBounds.xy;
    bool single = all(greaterThan(extent, vec2(0.0))) && any(notEqual(textureSize(gtexture, 0), atlasSize));
    vec2 uv = single ? spriteBounds.xy + vaUV0 * extent : vaUV0;
    vec2 middle = single ? spriteBounds.xy + mc_midTexCoord * extent : mc_midTexCoord;
    uint key = packUnorm2x16(clamp(middle, 0.0, 1.0)) + 1u;
    // A grass side can have a cutout overlay on top of its opaque base.
    // Keep distinct native sprites separate even if their geometry coincides.
    int layer = 0;
    uint existing = imageAtomicCompSwap(colorimg5, waterFaceAddress(face, 0), 0u, key);
    if (existing != 0u && existing != key) {
        layer = 1;
        existing = imageAtomicCompSwap(colorimg5, waterFaceAddress(face, 1), 0u, key);
        if (existing != 0u && existing != key) {
            imageAtomicOr(colorimg5, waterFaceAddress(face, 2), 16u);
            imageAtomicOr(colorimg5, waterFaceAddress(face, 3), 16u);
            return;
        }
    }
    float priority = 0.0;
    if (isMaskedTerrainSurface(gtexture, mc_midTexCoord, abs(vaUV0 - mc_midTexCoord))) {
        vec2 pixels = abs(vaUV0 - mc_midTexCoord) * 2.0 * vec2(textureSize(gtexture, 0));
        float lod = log2(max(max(pixels.x, pixels.y), 1.0));
        priority = 1.0 + round(14.0 * (1.0 - textureLod(gtexture, mc_midTexCoord, lod).a));
    }
    uvec3 tint = uvec3(round(clamp(vaColor.rgb, 0.0, 1.0) * vec3(31, 63, 31)));
    uint ao = uint(round(clamp(vaColor.a < 0.1 ? 1.0 : vaColor.a, 0.0, 1.0) * 15.0));
    uvec2 lm = uvec2(round(clamp(vec2(vaUV2) / 240.0, 0.0, 1.0) * 15.0));
    uint attributes = tint.x | (tint.y << 5u) | (tint.z << 11u) | (ao << 16u)
        | (lm.x << 20u) | (lm.y << 24u);
    if (glass) {
        uint alpha = uint(round(clamp(vaColor.a < 0.1 ? 1.0 : vaColor.a, 0.0, 1.0) * 255.0));
        attributes = (attributes & 0xfff0ffffu) | ((alpha & 15u) << 16u) | ((alpha >> 4u) << 28u);
    }
    imageAtomicExchange(colorimg5, waterFaceAddress(face, 4 + layer * 8 + corner), packUnorm2x16(uv));
    imageAtomicExchange(colorimg5, waterFaceAddress(face, 8 + layer * 8 + corner), attributes);
    // Keep coverage and the union of cutout priorities in the same atomic
    // word. Traversal can now select a layer without fetching its four colours.
    uint coverage = 1u << uint(corner + (glass ? 24 : 0));
    coverage |= priority > 0.0 ? 1u << (8u + uint(priority)) : 0u;
    uint previous = imageAtomicOr(colorimg5, waterFaceAddress(face, 2 + layer), coverage);
    if (previous == 0u) {
        imageAtomicOr(colorimg5, waterMacroAddress(waterMacroIndex(cell)), waterMacroBits(cell, axis, normal[axis] < 0.0));
        uint heightBand = 1u << uint(cell.y / waterHeightBand);
        imageAtomicOr(colorimg5, waterColumnAddress(waterColumnIndex(cell,4)), heightBand);
        imageAtomicOr(colorimg5, waterColumnAddress(waterColumnIndex(cell,16)), heightBand);
        if (glass) {
            imageAtomicOr(colorimg5, waterGlassColumn(waterColumnIndex(cell, 16) - waterSmallColumns), heightBand);
            int row = imageSize(colorimg5).y - 1;
            imageAtomicOr(colorimg5, ivec2(18, row), 1u << uint(cell.x / (waterFarSize.x / 32)));
            imageAtomicOr(colorimg5, ivec2(19, row), heightBand);
            imageAtomicOr(colorimg5, ivec2(20, row), 1u << uint(cell.z / (waterFarSize.z / 32)));
        }
    }
#endif
}

void main() {
#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
    vec3 lpvCentre = (shadowModelViewInverse * modelViewMatrix
        * vec4(vaPosition + nativeModelOffset(), 1.0)).xyz + cameraPosition + at_midBlock / 64.0;
    lpvCaptureGeometry(lpvCentre, at_midBlock);
#if GI_QUALITY > 0
    vec3 lpvAlbedo = textureLod(gtexture, mc_midTexCoord, 2.0).rgb * vaColor.rgb;
    lpvAlbedo = pow(max(lpvAlbedo, vec3(0.0)), vec3(2.2));
    lpvCaptureSurface(lpvCentre, mc_Entity.x == 106.0 ? 100 : int(round(mc_Entity.x)), lpvAlbedo,
        clamp(float(vaUV2.y) / 240.0, 0.0, 1.0));
#else
    lpvCaptureVertex(lpvCentre, mc_Entity.x == 106.0 ? 100 : int(round(mc_Entity.x)));
#endif
#endif

    float alias = mc_Entity.x == 106.0 ? 100.0 : mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    // 1. 世界空间 -> 太阳的裁剪空间
    vec3 position = vec4(vaPosition + nativeModelOffset(), 1.0).xyz;
    vCaster = abs(legacyEntity.x - 101.0) < 0.5 || abs(legacyEntity.x - 102.0) < 0.5 ? 1.0
            : abs(legacyEntity.x - 110.0) < 0.5 ? 2.0
            : abs(legacyEntity.x - 100.0) < 0.5 ? 3.0
            : hasFoliageWind(legacyEntity.x) ? 4.0 : 0.0;
    if (hasFoliageWind(legacyEntity.x)) {
        vec3 shadowViewPosition = (modelViewMatrix * vec4(vaPosition + nativeModelOffset(), 1.0)).xyz;
        vec3 worldPosition = (shadowModelViewInverse * vec4(shadowViewPosition, 1.0)).xyz
                           + cameraPosition;
        vec3 blockCenter = worldPosition + at_midBlock / 64.0;
        vec3 root = foliageRoot(blockCenter, legacyEntity.x);
        position += foliageWindOffset(worldPosition, root, legacyEntity.x);
    }
    vec4 shadowClipPos = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    // 保留原始三角形平面，片元阶段在真实阴影纹素中心重新求深度。
    vShadowPosition = shadowClipPos.xyz / shadowClipPos.w;

    // 2. 畸变。必须和 gbuffers 用的完全一致，否则采样位置会对不上。
    shadowClipPos.xyz = distortShadow(shadowClipPos.xyz);

    // 3. 交给 GPU 光栅化并写深度
    gl_Position = shadowClipPos;

    // 4. 透传贴图坐标与顶点颜色，供片元着色器做 alpha 测试
    vTexCoord = vaUV0;
    vCasterNormal = mat3(shadowModelViewInverse) * normalMatrix * vaNormal;
    vec3 nativeCentre = (shadowModelViewInverse * modelViewMatrix
        * vec4(vaPosition + nativeModelOffset(), 1.0)).xyz + cameraPosition + at_midBlock / 64.0;
    bool exitLayer = isTranslucentTerrainStage() && isEyeInWater == 1
        && WATER_REFRACTION_STRENGTH > 0.0 && abs(legacyEntity.x - 100.0) > 0.5;
    // Keep coordinates relative to the camera's integer position. The
    // geometry stage receives the positions actually used by this shadow draw.
    gNativePosition = vec3(0.0);
    if (exitLayer || abs(legacyEntity.x - 100.0) < 0.5
        || abs(vCaster - 1.0) < 0.1 || (!isTerrainStage())) {
        gNativePosition = (shadowModelViewInverse * modelViewMatrix * vec4(position, 1.0)).xyz
            + fract(cameraPosition);
    }
    gTransparentTriangle = int(exitLayer);
    waterCaptureFace(nativeCentre, normalize(vCasterNormal), exitLayer);
    ivec3 parity = ivec3(floor(nativeCentre)) & 1;
    vWaterFaceParity = (isOpaqueTerrainStage()) && all(lessThanEqual(abs(at_midBlock), vec3(32.01)))
        ? parity.x + 2 * parity.y + 4 * parity.z : -1;
    vCasterLight = clamp(vec2(vaUV2) / 240.0, 0.0, 1.0);
    vColor = vaColor;
    if (vColor.a < 0.1) {
        vColor.a = 1.0;
    }
}

