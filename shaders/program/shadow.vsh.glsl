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
#ifndef LIB_UNIFORMS_GLSL
#define LIB_UNIFORMS_GLSL


/* ============================================================================
 * 一、玩家摄像机的矩阵（gbuffer 系列）
 * ==========================================================================*/

// 世界空间 -> 视图空间。摄像机在原点，看向 -Z，+Y 朝上。
uniform mat4 gbufferModelView;

// 视图空间 -> 世界空间（摄像机相对）。提取法线方向时可以用 mat3() 取左上角。
uniform mat4 gbufferModelViewInverse;

// 视图空间 -> 裁剪空间（透视投影）。
uniform mat4 gbufferProjection;

// 裁剪空间 -> 视图空间。从深度缓冲还原真实坐标时必用。
uniform mat4 gbufferProjectionInverse;

// 上一帧的同名矩阵。做运动模糊、TAA、时域降噪时需要，
// 本基础光影暂时用不到，先声明出来方便后续扩展。
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

// Native OptiFine J9: terrain is 8 (solid), 9 (cutout), 16 (translucent).
// Entities=10, block entities=11 and solid hand=15 are separate geometry paths.
uniform int renderStage;


/* ============================================================================
 * 二、阴影摄像机的矩阵（shadow 系列）
 *    阴影贴图由"站在太阳位置"的虚拟摄像机渲染，它有独立的一套矩阵。
 *    把世界坐标乘上 shadowModelView * shadowProjection，就得到该点
 *    在太阳眼中的位置，进而算出阴影贴图上的采样坐标。
 * ==========================================================================*/

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;


/* ============================================================================
 * 三、摄像机与屏幕
 * ==========================================================================*/

// 摄像机的【绝对世界坐标】。视图空间坐标 + cameraPosition = 绝对世界坐标。
uniform vec3 cameraPosition;

// 上一帧的摄像机位置，同样为扩展预留。
uniform vec3 previousCameraPosition;

// 投影的近平面 / 远平面距离（单位：方块）。
// far 等于游戏设置里的渲染距离，是自定义雾的核心参数。
uniform float near;
uniform float far;

// 内部场景纹理分辨率（像素）与宽高比。final 的输出窗口可以是另一尺寸。
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

// 中心深度（屏幕正中央像素的深度），做自动对焦/景深时用。
uniform float centerDepthSmooth;


/* ============================================================================
 * 四、时间
 * ==========================================================================*/

// 当前游戏内时间，范围 [0, 24000)。0 = 日出，6000 = 正午，18000 = 日落。
uniform int worldTime;

// 累计游戏天数，可用来做"每天不一样"的随机。
uniform int worldDay;

// 从世界创建起累计的秒数（浮点）。做周期性动画（水波、闪烁）时用它，
// 比 worldTime 更平滑，因为它是连续的浮点而不是整数 tick。
uniform float frameTimeCounter;
// 每帧秒数用于介质状态的时间平滑，响应速度不依赖帧率。
uniform float frameTime;

// 已渲染的帧数。做抖动（dither）时用它让每帧噪声不同。
uniform int frameCounter;


/* ============================================================================
 * 五、光照与天空
 * ==========================================================================*/

// 太阳 / 月亮在【视图空间】中的位置，长度约为 100。
// 用 normalize() 之后即可当作"从表面指向光源"的方向向量。
uniform vec3 sunPosition;
uniform vec3 moonPosition;

// 世界空间的"正上方"方向在视图空间中的表示。
// 想判断"这个东西是不是朝上的"时用得到（比如让草顶面更亮）。
uniform vec3 upPosition;

// 天顶颜色，随时间和天气变化；地平线颜色由 fogColor 提供。
uniform vec3 skyColor;

// 当前"投出阴影的光源"在视图空间中的位置（白天是太阳，夜晚是月亮）。
uniform vec3 shadowLightPosition;

// 月相，0 = 满月 …… 4 = 新月。可用于调整夜晚亮度。
uniform int moonPhase;


/* ============================================================================
 * 六、天气与环境
 * ==========================================================================*/

// 雨的强度，范围 [0,1]。0 = 晴天，1 = 暴雨。
uniform float rainStrength;

// 地表湿度，范围 [0,1]。下雨时会逐渐升高，雨停后缓慢下降。
// 常用于让方块表面变暗、变光滑。
uniform float wetness;

// 摄像机的高度（y 坐标）。可以做"越高越亮"的大气效果。
uniform float eyeAltitude;

// 摄像机所处位置的平滑亮度，x 为方块光，y 为天空光。
// 类型与 OptiFine 保持一致；使用时再按需归一化到 [0,1]。
uniform ivec2 eyeBrightnessSmooth;

// 摄像机是否在液体/方块内：0 = 空气，1 = 水，2 = 岩浆，3 = 细雪。
uniform int isEyeInWater;

// 地平线雾色是 RGB 三分量。必须与 OptiFine 的 uniform 类型一致；
// 声明成 vec4 会让 glUniform3f 产生 GL_INVALID_OPERATION，雾色无法更新。
uniform vec3 fogColor;
uniform float fogDensity;

// 屏幕亮度、夜视、失明等状态效果。
uniform float screenBrightness;
uniform float nightVision;
uniform float blindness;


/* ============================================================================
 * 七、渲染状态
 * ==========================================================================*/

// 当前程序的 alpha 测试阈值。
// 贴图 alpha 小于它的像素会被丢弃。
// 对于不透明程序，这个值是游戏设置里的"树叶/草透明"相关阈值；
// 对于 _a（半透明）程序，OptiFine 会把它设为 0，于是不会误丢像素。
uniform float alphaTestRef;

// 实体着色（受伤变红等）的叠加颜色。
uniform vec4 entityColor;

// 当前绑定的方块图集大小（单位：像素），做像素级贴图操作时需要。
uniform ivec2 atlasSize;


#endif  // LIB_UNIFORMS_GLSL


#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
uniform sampler2D colortex8;
// J9 restores every shadow draw attachment during native terrain submission.
// Fixed-size C5 is detached from the scene FBO and cannot be overwritten by
// raster outputs. Image reads also avoid J9's forced LINEAR sampler filtering.
layout(r32ui, binding=5) uniform uimage2D colorimg5;
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
    if (renderStage != 8 && renderStage != 9 && renderStage != 16) return;
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
    if (renderStage != 8 && renderStage != 9 && renderStage != 16) return;
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
    if (renderStage != 8 && renderStage != 9 && renderStage != 16) return;
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
uniform vec3 modelOffset;
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
#ifndef LIB_UNIFORMS_GLSL
#define LIB_UNIFORMS_GLSL


/* ============================================================================
 * 一、玩家摄像机的矩阵（gbuffer 系列）
 * ==========================================================================*/

// 世界空间 -> 视图空间。摄像机在原点，看向 -Z，+Y 朝上。
uniform mat4 gbufferModelView;

// 视图空间 -> 世界空间（摄像机相对）。提取法线方向时可以用 mat3() 取左上角。
uniform mat4 gbufferModelViewInverse;

// 视图空间 -> 裁剪空间（透视投影）。
uniform mat4 gbufferProjection;

// 裁剪空间 -> 视图空间。从深度缓冲还原真实坐标时必用。
uniform mat4 gbufferProjectionInverse;

// 上一帧的同名矩阵。做运动模糊、TAA、时域降噪时需要，
// 本基础光影暂时用不到，先声明出来方便后续扩展。
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

// Native OptiFine J9: terrain is 8 (solid), 9 (cutout), 16 (translucent).
// Entities=10, block entities=11 and solid hand=15 are separate geometry paths.
uniform int renderStage;


/* ============================================================================
 * 二、阴影摄像机的矩阵（shadow 系列）
 *    阴影贴图由"站在太阳位置"的虚拟摄像机渲染，它有独立的一套矩阵。
 *    把世界坐标乘上 shadowModelView * shadowProjection，就得到该点
 *    在太阳眼中的位置，进而算出阴影贴图上的采样坐标。
 * ==========================================================================*/

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;


/* ============================================================================
 * 三、摄像机与屏幕
 * ==========================================================================*/

// 摄像机的【绝对世界坐标】。视图空间坐标 + cameraPosition = 绝对世界坐标。
uniform vec3 cameraPosition;

// 上一帧的摄像机位置，同样为扩展预留。
uniform vec3 previousCameraPosition;

// 投影的近平面 / 远平面距离（单位：方块）。
// far 等于游戏设置里的渲染距离，是自定义雾的核心参数。
uniform float near;
uniform float far;

// 内部场景纹理分辨率（像素）与宽高比。final 的输出窗口可以是另一尺寸。
uniform float viewWidth;
uniform float viewHeight;
uniform float aspectRatio;

// 中心深度（屏幕正中央像素的深度），做自动对焦/景深时用。
uniform float centerDepthSmooth;


/* ============================================================================
 * 四、时间
 * ==========================================================================*/

// 当前游戏内时间，范围 [0, 24000)。0 = 日出，6000 = 正午，18000 = 日落。
uniform int worldTime;

// 累计游戏天数，可用来做"每天不一样"的随机。
uniform int worldDay;

// 从世界创建起累计的秒数（浮点）。做周期性动画（水波、闪烁）时用它，
// 比 worldTime 更平滑，因为它是连续的浮点而不是整数 tick。
uniform float frameTimeCounter;
// 每帧秒数用于介质状态的时间平滑，响应速度不依赖帧率。
uniform float frameTime;

// 已渲染的帧数。做抖动（dither）时用它让每帧噪声不同。
uniform int frameCounter;


/* ============================================================================
 * 五、光照与天空
 * ==========================================================================*/

// 太阳 / 月亮在【视图空间】中的位置，长度约为 100。
// 用 normalize() 之后即可当作"从表面指向光源"的方向向量。
uniform vec3 sunPosition;
uniform vec3 moonPosition;

// 世界空间的"正上方"方向在视图空间中的表示。
// 想判断"这个东西是不是朝上的"时用得到（比如让草顶面更亮）。
uniform vec3 upPosition;

// 天顶颜色，随时间和天气变化；地平线颜色由 fogColor 提供。
uniform vec3 skyColor;

// 当前"投出阴影的光源"在视图空间中的位置（白天是太阳，夜晚是月亮）。
uniform vec3 shadowLightPosition;

// 月相，0 = 满月 …… 4 = 新月。可用于调整夜晚亮度。
uniform int moonPhase;


/* ============================================================================
 * 六、天气与环境
 * ==========================================================================*/

// 雨的强度，范围 [0,1]。0 = 晴天，1 = 暴雨。
uniform float rainStrength;

// 地表湿度，范围 [0,1]。下雨时会逐渐升高，雨停后缓慢下降。
// 常用于让方块表面变暗、变光滑。
uniform float wetness;

// 摄像机的高度（y 坐标）。可以做"越高越亮"的大气效果。
uniform float eyeAltitude;

// 摄像机所处位置的平滑亮度，x 为方块光，y 为天空光。
// 类型与 OptiFine 保持一致；使用时再按需归一化到 [0,1]。
uniform ivec2 eyeBrightnessSmooth;

// 摄像机是否在液体/方块内：0 = 空气，1 = 水，2 = 岩浆，3 = 细雪。
uniform int isEyeInWater;

// 地平线雾色是 RGB 三分量。必须与 OptiFine 的 uniform 类型一致；
// 声明成 vec4 会让 glUniform3f 产生 GL_INVALID_OPERATION，雾色无法更新。
uniform vec3 fogColor;
uniform float fogDensity;

// 屏幕亮度、夜视、失明等状态效果。
uniform float screenBrightness;
uniform float nightVision;
uniform float blindness;


/* ============================================================================
 * 七、渲染状态
 * ==========================================================================*/

// 当前程序的 alpha 测试阈值。
// 贴图 alpha 小于它的像素会被丢弃。
// 对于不透明程序，这个值是游戏设置里的"树叶/草透明"相关阈值；
// 对于 _a（半透明）程序，OptiFine 会把它设为 0，于是不会误丢像素。
uniform float alphaTestRef;

// 实体着色（受伤变红等）的叠加颜色。
uniform vec4 entityColor;

// 当前绑定的方块图集大小（单位：像素），做像素级贴图操作时需要。
uniform ivec2 atlasSize;


#endif  // LIB_UNIFORMS_GLSL

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
#ifndef LIB_COMMON_GLSL
#define LIB_COMMON_GLSL

/* ---------------------------------------------------------------------------
 * 常量
 * ------------------------------------------------------------------------ */

// 圆周率。GLSL 没有内置的 PI，必须自己定义。
#define PI 3.141592653589793
#define TAU 6.283185307179586

// 半个圆周率，用于把 [-1,1] 映射到 [0,PI] 之类的场景。
#define HALF_PI 1.570796326794897

// 极小值。用来避免除零、以及作为浮点数比较的容差。
#define EPSILON 1e-5


/* ---------------------------------------------------------------------------
 * 数学工具
 * ------------------------------------------------------------------------ */

// 平方。写成函数而不是 pow(x, 2.0)，因为 pow 内部走的是 exp/log，慢得多。
float square(float x) {
    return x * x;
}

// 四次方。常用于把 NdotL 之类的衰减曲线压得更"硬"。
float pow4(float x) {
    float x2 = x * x;
    return x2 * x2;
}

// 感知亮度（Rec.709 权重）。
// 人眼对绿色最敏感、蓝色最不敏感，所以绿色权重最大。
// 灰度化、色调映射、亮度阈值判断都要用它，不能简单取 (r+g+b)/3。
float luma(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// 线性重映射：把 value 从 [inMin, inMax] 映射到 [outMin, outMax]。
// 不做 clamp，超出范围会外推。
float remap(float value, float inMin, float inMax, float outMin, float outMax) {
    return outMin + (value - inMin) / (inMax - inMin) * (outMax - outMin);
}

// 按亮度饱和度和插值地调整颜色的"鲜艳程度"。
// amount = 0 得到灰度，1 保持原色，> 1 会过饱和。
vec3 applySaturation(vec3 color, float amount) {
    float gray = luma(color);
    return mix(vec3(gray), color, amount);
}

// 以中灰 0.5 为轴心调整对比度。
// amount = 1 不变，> 1 更硬，< 1 更平。
vec3 applyContrast(vec3 color, float amount) {
    return (color - 0.5) * amount + 0.5;
}

// 安全归一化：向量长度接近 0 时返回 fallback。
// 直接 normalize(vec3(0)) 会得到 NaN，NaN 一旦进入光照计算就会传染，
// 表现为整块屏幕变黑或闪烁，非常难排查。
vec3 safeNormalize(vec3 v, vec3 fallback) {
    float len = length(v);
    return len > EPSILON ? v / len : fallback;
}


/* ---------------------------------------------------------------------------
 * 法线编码 / 解码
 * ------------------------------------------------------------------------ */

// G-Buffer 里只用 RG 两个 8 位通道存法线，节省带宽。
// 八面体折叠保存完整球面，保留掠射面可能为负的 z 分量。
vec2 encodeNormal(vec3 normal) {
    normal /= max(abs(normal.x) + abs(normal.y) + abs(normal.z), EPSILON);
    vec2 p = normal.xy;
    if (normal.z < 0.0) {
        p = (1.0 - abs(p.yx)) * vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
    }
    return p * 0.5 + 0.5;
}

vec3 decodeNormal(vec2 encoded) {
    vec2 p = encoded * 2.0 - 1.0;
    vec3 normal = vec3(p, 1.0 - abs(p.x) - abs(p.y));
    float fold = clamp(-normal.z, 0.0, 1.0);
    normal.xy += vec2(normal.x >= 0.0 ? -fold : fold, normal.y >= 0.0 ? -fold : fold);
    return normalize(normal);
}


/* ---------------------------------------------------------------------------
 * 材质标记
 *   把"这是什么物体"这条信息一路带到后处理阶段，
 *   后面想给水做屏幕空间反射、给树叶做风摆动，都靠它来区分。
 * ------------------------------------------------------------------------ */
#define MAT_SOLID   0.20
#define MAT_WATER   0.45
#define MAT_FOLIAGE 0.70
#define MAT_ENTITY  1.00
#define MAT_WET_GROUND 0.85


/* ---------------------------------------------------------------------------
 * 哈希与伪随机
 *   GLSL 没有随机数。同一个像素每帧的结果必须一致，所以只能用
 *   "位置 -> 固定数值" 的哈希函数。常用在抖动、噪波、闪烁效果上。
 * ------------------------------------------------------------------------ */

// 输入一个二维坐标，输出 [0,1) 之间的伪随机数。
// fract(sin(dot(...))) 是图形学里最经典的哈希写法，代价低且分布够用。
float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 输入三维坐标，输出 [0,1) 之间的伪随机数。
float hash13(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

#endif  // LIB_COMMON_GLSL

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#ifndef LIB_SPACE_GLSL
#define LIB_SPACE_GLSL






/* ---------------------------------------------------------------------------
 * 视图空间 <-> 世界空间
 * ------------------------------------------------------------------------ */

// 视图空间 -> 世界空间（结果以摄像机为原点，即"摄像机相对世界坐标"）。
// 注意这个结果不是绝对世界坐标，想拿绝对坐标还要再加 cameraPosition。
vec3 viewToWorld(vec3 viewPos) {
    return (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
}

// 视图空间 -> 绝对世界坐标。
// cameraPosition 是摄像机的绝对位置，两者相加才得到 Minecraft 世界里的真实坐标。
vec3 viewToAbsoluteWorld(vec3 viewPos) {
    return viewToWorld(viewPos) + cameraPosition;
}

// 世界空间（摄像机相对） -> 视图空间
vec3 worldToView(vec3 worldPos) {
    return (gbufferModelView * vec4(worldPos, 1.0)).xyz;
}


/* ---------------------------------------------------------------------------
 * 深度
 *   depthtex0 里存的深度是非线性的：经过透视投影后，近处精度极高，
 *   远处精度极低（这就是"z-fighting"的根源）。想拿真实距离必须还原。
 * ------------------------------------------------------------------------ */

// 把 [0,1] 的深度缓冲值还原成视图空间的线性距离（单位：方块）。
// 公式来源：把 NDC 深度代回投影矩阵的逆推导，适用于标准透视投影。
float linearizeDepth(float depth) {
    float ndcDepth = depth * 2.0 - 1.0;             // [0,1] -> [-1,1]
    return (2.0 * near * far) / (far + near - ndcDepth * (far - near));
}

// 由屏幕 UV + 深度缓冲值还原视图空间坐标。
// 这是屏幕空间效果（SSAO、屏幕空间反射、体积光）的第一步。
vec3 screenToView(vec2 uv, float depth) {
    // UV [0,1] 先变回 NDC [-1,1]
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndc;
    return viewPos.xyz / viewPos.w;                 // 透视除法，还原到真实位置
}


/* ---------------------------------------------------------------------------
 * 屏幕坐标工具
 *
 * ⚠️ 注意：本文件会被【顶点着色器】一起包含（顶点变换也要用矩阵）。
 *    所以这里绝不能出现 gl_FragCoord / gl_FragData 这类片元专用的内置变量，
 *    否则顶点着色器会直接编译失败。
 *    内部全分辨率阶段的 UV 因此在对应 .fsh 里现算：
 *        vec2 screenCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
 *    final 输出到窗口，必须使用顶点传入的归一化 UV；加载器的
 *    渲染精细度会使窗口尺寸与 viewWidth/Height 不同。
 * ------------------------------------------------------------------------ */

// 像素尺寸：一个像素在 UV 空间中的大小，采样邻域时用。
vec2 getTexelSize() {
    return 1.0 / vec2(viewWidth, viewHeight);
}

// 做模糊/泛光时，需要用宽高比校正采样偏移，
// 否则在宽屏上圆形核会被拉成椭圆。
vec2 aspectCorrect(vec2 offset) {
    return offset * vec2(1.0, viewWidth / viewHeight);
}


/* ---------------------------------------------------------------------------
 * 阴影贴图畸变
 *   阴影贴图是正交投影，覆盖了 shadowDistance 范围内的一个方盒子。
 *   离摄像机越远的地方，一个纹素覆盖的实际面积越大（近处很精细，
 *   远处很粗糙）。把裁剪空间坐标按距离向外拉伸，等于把纹素"重新分配"：
 *   近处纹理占用变多、远处占用变少，整体精度更均匀。
 *
 *   注意：顶点着色器和片元着色器必须用完全相同的畸变函数，
 *   否则投影出来的位置和采样的位置对不上，阴影会整体错位。
 * ------------------------------------------------------------------------ */
// 加载器会缩放阴影附件，并将尺寸四舍五入到整数纹素。
float shadowTextureResolution() {
#ifdef MC_SHADOW_QUALITY
    return max(floor(float(shadowMapResolution) * MC_SHADOW_QUALITY + 0.5), 1.0);
#else
    return float(shadowMapResolution);
#endif
}

vec3 distortShadow(vec3 clipPos) {
    float dist = length(clipPos.xy);                // 距离屏幕中心的距离，范围约 [0, 1.41]
    // ---------------------------------------------------------------
    // factor = (1 - BIAS) + dist * BIAS
    //
    //   BIAS = 0.0  -> factor 恒等于 1        -> xy 不变，【不畸变】
    //   BIAS = 0.9  -> 中心 factor = 0.1，边缘 factor = 1.0
    //                  xy 被除以一个小数 -> 中心附近的坐标被推向边缘
    //                  -> 贴图中心区域占用的纹素变多（近处更精细）✅
    //   BIAS = 1.0  -> factor = dist，除以它会得到单位向量
    //                  -> 【退化成全屏塌缩】，不要用这个值
    //
    // 所以 BIAS 越大畸变越强，常用 0.9，取值必须小于 1。
    // ---------------------------------------------------------------
    float factor = (1.0 - SHADOW_MAP_BIAS) + dist * SHADOW_MAP_BIAS;
    clipPos.xy /= factor;
    return clipPos;
}

// 将阴影纹素中心反解到未畸变的裁剪平面，供光栅深度校正使用。
vec2 undistortShadow(vec2 distorted) {
    float denominator = max(1.0 - SHADOW_MAP_BIAS * length(distorted), EPSILON);
    return distorted * (1.0 - SHADOW_MAP_BIAS) / denominator;
}

// 把畸变后的裁剪空间坐标转成可以直接采样的 UV + 深度。
// 透视除法在这里显式做，因为畸变是在除法【之前】施加的。
vec3 shadowClipToUv(vec4 shadowClipPos) {
    vec3 ndc = shadowClipPos.xyz / shadowClipPos.w; // 裁剪空间 -> NDC [-1,1]
    return ndc * 0.5 + 0.5;                         // NDC -> [0,1]，同时得到 UV 和深度
}

#endif  // LIB_SPACE_GLSL

/*
 * 植被顶点风摆。地形和阴影共用世界坐标、时间、分类与位移函数。
 * 叶片采用连续空间场以保持相邻方块接缝；草/花/作物以根部为固定支点。
 * 两格植物的上下部分使用同一根部、相位和高度曲线。
 */
#ifndef LIB_FOLIAGE_WIND_GLSL
#define LIB_FOLIAGE_WIND_GLSL





const float WIND_LEAVES_ID = 200.0;
const float WIND_PLANT_ID = 201.0;
const float WIND_TALL_LOWER_ID = 202.0;
const float WIND_TALL_UPPER_ID = 203.0;
const float WIND_CROP_ID = 204.0;

bool hasFoliageWind(float material) {
    return material >= 199.5 && material <= 204.5;
}

// 有界哈希只作用于植株根部，相邻面及双格植物不会得到不同的随机相位。
float plantWindHash(vec3 root) {
    vec3 value = fract(root * vec3(0.1031, 0.1030, 0.0973));
    value += dot(value, value.yzx + 33.33);
    return fract((value.x + value.y) * value.z);
}

// 坐标在变形前计算；顶点到方块中心的属性精度为 1/64 方块。
vec3 foliageRoot(vec3 blockCenter, float material) {
    vec3 root = floor(blockCenter + 0.001);
    root.xz += 0.5;
    if (abs(material - WIND_TALL_UPPER_ID) < 0.5) {
        root.y -= 1.0;
    }
    return root;
}

float foliageWindTime() {
    return frameTimeCounter * WIND_SPEED;
}

// 大尺度风向与缓慢阵风共用；雨天适度增强，细节运动的周期彼此错开。
vec3 foliageWindOffset(vec3 worldPosition, vec3 root, float material) {
#if ENABLE_FOLIAGE_WIND == 0
    return vec3(0.0);
#else
    if (!hasFoliageWind(material) || WIND_STRENGTH <= 0.0) {
        return vec3(0.0);
    }
    float time = foliageWindTime();
    vec2 direction = normalize(vec2(0.92, 0.39));
    vec2 crosswind = vec2(-direction.y, direction.x);
    float weather = 1.0 + rainStrength * 0.35;
    if (abs(material - WIND_LEAVES_ID) < 0.5) {
        // 对共享顶点使用同一位置函数，避免叶团分裂成独立摇晃的小方块。
        float phase = dot(worldPosition, vec3(0.16, 0.11, 0.13));
        float broad = sin(phase - time * 1.35) * 0.72;
        float flutter = sin(phase * 2.7 + time * 2.10) * 0.28;
        float sideways = sin(phase * 1.4 - time * 1.73 + 1.7) * 0.30;
        vec2 horizontal = direction * (broad + flutter) + crosswind * sideways;
        float vertical = sin(phase * 1.8 + time * 1.60) * 0.18;
        return vec3(horizontal.x, vertical, horizontal.y)
             * LEAF_SWAY_STRENGTH * WIND_STRENGTH * weather;
    }

    bool tall = abs(material - WIND_TALL_LOWER_ID) < 0.5
             || abs(material - WIND_TALL_UPPER_ID) < 0.5;
    float span = tall ? 2.0 : 1.0;
    float height = max(worldPosition.y - root.y, 0.0);
    float bend = clamp(height / span, 0.0, 1.0);
    bend *= bend;
    float phase = plantWindHash(root) * (2.0 * PI) + dot(root.xz, vec2(0.055, 0.081));
    float gust = 0.70 + 0.30 * sin(dot(root.xz, vec2(0.037, -0.026)) - time * 0.37);
    float sway = sin(time * 1.55 + phase) * 0.72 + sin(time * 2.83 + phase * 1.37) * 0.28;
    float side = sin(time * 1.19 + phase * 1.73) * 0.22;
    float cropScale = abs(material - WIND_CROP_ID) < 0.5 ? 0.75 : 1.0;
    vec2 horizontal = (direction * sway + crosswind * side) * gust * bend * span
                    * PLANT_SWAY_STRENGTH * WIND_STRENGTH * cropScale * weather;
    // 小角度弯曲的高度补偿，根部高度及水平坐标均严格保持不动。
    float vertical = -0.5 * dot(horizontal, horizontal) / max(height, 0.1);
    return vec3(horizontal.x, vertical, horizontal.y);
#endif
}

// 叶片只依赖一个空间相位，可直接求位移雅可比；植株只随根部高度变化，
// 复用已经求得的位移计算高度差分。两者都不再重复四次完整的风场与哈希。
vec3 foliageWindNormal(vec3 worldPosition, vec3 root, float material,
                       vec3 normalWorld, vec3 displacement) {
#if ENABLE_FOLIAGE_WIND == 0
    return normalWorld;
#else
    if (!hasFoliageWind(material) || WIND_STRENGTH <= 0.0) {
        return normalWorld;
    }
    vec3 derivative;
    vec3 gradient;
    if (abs(material - WIND_LEAVES_ID) < 0.5) {
        float time = foliageWindTime();
        float phase = dot(worldPosition, vec3(0.16, 0.11, 0.13));
        vec2 direction = normalize(vec2(0.92, 0.39));
        vec2 crosswind = vec2(-direction.y, direction.x);
        float along = cos(phase - time * 1.35) * 0.72
                    + cos(phase * 2.7 + time * 2.10) * (0.28 * 2.7);
        float side = cos(phase * 1.4 - time * 1.73 + 1.7) * (0.30 * 1.4);
        vec2 horizontal = direction * along + crosswind * side;
        float vertical = cos(phase * 1.8 + time * 1.60) * (0.18 * 1.8);
        derivative = vec3(horizontal.x, vertical, horizontal.y)
                   * LEAF_SWAY_STRENGTH * WIND_STRENGTH * (1.0 + rainStrength * 0.35);
        gradient = vec3(0.16, 0.11, 0.13);
    } else {
        bool tall = abs(material - WIND_TALL_LOWER_ID) < 0.5
                 || abs(material - WIND_TALL_UPPER_ID) < 0.5;
        float span = tall ? 2.0 : 1.0;
        float height = max(worldPosition.y - root.y, 0.0);
        float bend = clamp(height / span, 0.0, 1.0);
        if (bend <= 0.0001) {
            return normalWorld;
        }
        // 保留根部、顶端限幅及高度补偿的原有边界行为；这里只做标量差分，
        // 不重复依赖根部哈希和时间的三角函数。
        const float epsilon = 0.02;
        float upper = square(clamp((height + epsilon) / span, 0.0, 1.0)) / square(bend);
        float lower = square(clamp((height - epsilon) / span, 0.0, 1.0)) / square(bend);
        vec2 horizontal = displacement.xz * (upper - lower) / (2.0 * epsilon);
        float squared = dot(displacement.xz, displacement.xz);
        float upperY = -0.5 * squared * upper * upper / max(height + epsilon, 0.1);
        float lowerY = -0.5 * squared * lower * lower / max(height - epsilon, 0.1);
        derivative = vec3(horizontal.x, (upperY - lowerY) / (2.0 * epsilon), horizontal.y);
        gradient = vec3(0.0, 1.0, 0.0);
    }
    vec3 reference = abs(normalWorld.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(reference, normalWorld));
    vec3 bitangent = cross(normalWorld, tangent);
    vec3 deformedTangent = tangent + derivative * dot(gradient, tangent);
    vec3 deformedBitangent = bitangent + derivative * dot(gradient, bitangent);
    return safeNormalize(cross(deformedTangent, deformedBitangent), normalWorld);
#endif
}

// 独立探针或其它调用方未缓存位移时仍可使用原接口。
vec3 foliageWindNormal(vec3 worldPosition, vec3 root, float material, vec3 normalWorld) {
    return foliageWindNormal(worldPosition, root, material, normalWorld,
                             foliageWindOffset(worldPosition, root, material));
}

#endif



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
#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
#include "/lib/water_face_cache.glsl"

// Each corner carries its active atlas UV, tint, AO and light levels.
// Transparent terrain has its own class and can never supply an opaque hit.
void waterCaptureFace(vec3 centre, vec3 normal, bool glass) {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (renderStage != 8 && renderStage != 9 && !glass) return;
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
    if (renderStage == 9) {
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
        uint heightBand = 1u << uint(cell.y >> 1);
        imageAtomicOr(colorimg5, waterColumnAddress(waterColumnIndex(cell,4)), heightBand);
        imageAtomicOr(colorimg5, waterColumnAddress(waterColumnIndex(cell,16)), heightBand);
        if (glass) {
            imageAtomicOr(colorimg5, waterGlassColumn(waterColumnIndex(cell, 16) - 1024), heightBand);
            int row = imageSize(colorimg5).y - 1;
            imageAtomicOr(colorimg5, ivec2(18, row), 1u << uint(cell.x >> 2));
            imageAtomicOr(colorimg5, ivec2(19, row), heightBand);
            imageAtomicOr(colorimg5, ivec2(20, row), 1u << uint(cell.z >> 2));
        }
    }
#endif
}

void main() {
#if ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0
    vec3 lpvCentre = (shadowModelViewInverse * modelViewMatrix
        * vec4(vaPosition + modelOffset, 1.0)).xyz + cameraPosition + at_midBlock / 64.0;
    lpvCaptureGeometry(lpvCentre, at_midBlock);
#if GI_QUALITY > 0
    vec3 lpvAlbedo = textureLod(gtexture, mc_midTexCoord, 2.0).rgb * vaColor.rgb;
    lpvAlbedo = pow(max(lpvAlbedo, vec3(0.0)), vec3(2.2));
    lpvCaptureSurface(lpvCentre, int(round(mc_Entity.x)), lpvAlbedo,
        clamp(float(vaUV2.y) / 240.0, 0.0, 1.0));
#else
    lpvCaptureVertex(lpvCentre, int(round(mc_Entity.x)));
#endif
#endif

    float alias = mc_Entity.x;
    if (alias >= 6000.0 && alias <= 6010.0) {
        alias = alias == 6000.0 || alias == 6003.0 || alias == 6010.0 ? 101.0 : 102.0;
    }
    vec2 legacyEntity = vec2(alias, mc_Entity.y);
    // 1. 世界空间 -> 太阳的裁剪空间
    vec3 position = vec4(vaPosition + modelOffset, 1.0).xyz;
    vCaster = abs(legacyEntity.x - 101.0) < 0.5 || abs(legacyEntity.x - 102.0) < 0.5 ? 1.0
            : abs(legacyEntity.x - 110.0) < 0.5 ? 2.0
            : abs(legacyEntity.x - 100.0) < 0.5 ? 3.0
            : hasFoliageWind(legacyEntity.x) ? 4.0 : 0.0;
    if (hasFoliageWind(legacyEntity.x)) {
        vec3 shadowViewPosition = (modelViewMatrix * vec4(vaPosition + modelOffset, 1.0)).xyz;
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
        * vec4(vaPosition + modelOffset, 1.0)).xyz + cameraPosition + at_midBlock / 64.0;
    bool exitLayer = renderStage == 16 && isEyeInWater == 1
        && WATER_REFRACTION_STRENGTH > 0.0 && abs(legacyEntity.x - 100.0) > 0.5;
    // Keep coordinates relative to the camera's integer position. The
    // geometry stage receives the positions actually used by this shadow draw.
    gNativePosition = vec3(0.0);
    if (exitLayer) {
        gNativePosition = (shadowModelViewInverse * modelViewMatrix * vec4(position, 1.0)).xyz
            + fract(cameraPosition);
    }
    gTransparentTriangle = int(exitLayer);
    waterCaptureFace(nativeCentre, normalize(vCasterNormal), exitLayer);
    ivec3 parity = ivec3(floor(nativeCentre)) & 1;
    vWaterFaceParity = (renderStage == 8 || renderStage == 9) && all(lessThanEqual(abs(at_midBlock), vec3(32.01)))
        ? parity.x + 2 * parity.y + 4 * parity.z : -1;
    vCasterLight = clamp(vec2(vaUV2) / 240.0, 0.0, 1.0);
    vColor = vaColor;
    if (vColor.a < 0.1) {
        vColor.a = 1.0;
    }
}

