/* Diffuse transport uses a conservative six-lobe angular stencil. Free-space
 * transport preserves energy, while material reflectance bounds feedback.
 * Direct sunlight, native skylight and independently occluded lamps seed only
 * exposed solid faces. The field therefore contains bounced light exclusively.
 */
/* RENDERTARGETS: 12 */
/* Six directional radiance lobes in a camera-relative voxel volume. A lobe
 * travels through air and reflects at the exposed face of an opaque voxel.
 * Separate faces prevent a lit exterior from illuminating a sealed interior.
 * Headers store the field's own origin, independent of the direct-light passes.
 */
#ifndef SIMPLE_CONVENTIONAL_GI_GLSL
#define SIMPLE_CONVENTIONAL_GI_GLSL
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

#if GI_QUALITY > 0
uniform sampler2D colortex12;

ivec3 giDirection(int face) {
    ivec3 direction = ivec3(0);
    direction[face / 2] = face % 2 == 0 ? 1 : -1;
    return direction;
}

ivec2 giAddress(ivec3 cell, int face) {
    return lpvAddress(cell) + ivec2(0, face * textureSize(colortex8, 0).y);
}

ivec3 giStoredOrigin() {
    int height = textureSize(colortex8, 0).y;
    vec3 high = texelFetch(colortex12, ivec2(1, 0), 0).xyz;
    vec3 middle = texelFetch(colortex12, ivec2(1, height), 0).xyz;
    vec3 low = texelFetch(colortex12, ivec2(1, height * 2), 0).xyz;
    return ivec3(round(high * 1048576.0 + middle * 1024.0 + low));
}

bool giHistoryValid() {
    vec4 header = texelFetch(colortex12, ivec2(0), 0);
    int delta = (frameCounter - lpvHeaderFrame(header) + 720720) % 720720;
    ivec3 origin = giStoredOrigin();
    return header.w == 1973.0 && int(round(header.x)) == lpvShape().x
        && delta <= 1 && all(lessThanEqual(abs(lpvOrigin(cameraPosition) - origin), ivec3(2)));
}

// Reads always use the stored origin, so substeps and integer camera movement
// share the same mapping. Newly uncovered cells receive no stale radiance.
vec3 giRead(ivec3 cell, int face, ivec3 shift) {
    ivec3 previous = cell + shift;
    if (!lpvInside(cell) || !lpvInside(previous)) return vec3(0.0);
    return max(texelFetch(colortex12, giAddress(previous, face), 0).rgb, vec3(0.0));
}

// The six-lobe quadrature integrates the normal-facing radiance. Sampling only
// air prevents interpolation with the bright opposite face of a one-block wall.
vec3 giSurfaceIrradiance(vec3 viewPosition, vec3 normalView) {
    if (GI_STRENGTH <= 0.0 || !giHistoryValid()) return vec3(0.0);
    vec3 normal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 relative = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 world = relative + cameraPosition + normal * 0.55;
    vec3 position = world - vec3(lpvOrigin(cameraPosition)) - 0.5;
    ivec3 first = ivec3(floor(position));
    vec3 fraction = fract(position);
    vec3 irradiance = vec3(0.0);
    float total = 0.0;
    for (int corner = 0; corner < 8; corner++) {
        ivec3 offset = ivec3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1);
        ivec3 cell = first + offset;
        if (!lpvInside(cell) || lpvOpaque(lpvVoxel(cell))) continue;
        vec3 blend = mix(1.0 - fraction, fraction, vec3(offset));
        float weight = blend.x * blend.y * blend.z;
        for (int axis = 0; axis < 3; axis++) {
            int face = axis * 2 + (normal[axis] > 0.0 ? 1 : 0);
            irradiance += texelFetch(colortex12, giAddress(cell, face), 0).rgb
                * abs(normal[axis]) * weight;
        }
        total += weight;
    }
    vec3 border = vec3(lpvShape()) * 0.5 - abs(relative + normal * 0.55);
    float coverage = smoothstep(1.0, 5.0, min(border.x, min(border.y, border.z)));
    return max(irradiance, vec3(0.0)) / max(total, 0.001) * GI_STRENGTH * coverage;
}
#endif
#endif

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_shadow.glsl"

/* 表面光照。分别计算日月直射、天空环境光与局部方块光；AO 作用于间接项。
 * 配套数据就绪时接入独立点光阴影和体素 GI，其他情况使用原版光照场。
 */
#include "/lib/lighting/lighting_transport.glsl"

layout(location=0) out vec4 result;

#if GI_QUALITY > 0
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

// Native sky levels constrain exposure, but a single block can have lit and
// unlit faces. Test the air column outside this face before injecting sky energy.
float giSkyVisibility(ivec3 air) {
    for (int stepIndex = 0; stepIndex < COLOURED_VOLUME_SIZE / 2; stepIndex++) {
        if (!lpvInside(air)) return 1.0;
        uint voxel = lpvVoxel(air);
        if (lpvOpaque(voxel)) return 0.0;
        air.y++;
    }
    return 0.0;
}

// A surface offset avoids its own depth without extending through neighbouring
// blocks. Outside the real shadow coverage no unverified sunlight is injected.
float giSunVisibility(vec3 world, vec3 normal) {
    vec4 clip = shadowProjection * shadowModelView
        * vec4(world + normal * 0.06 - cameraPosition, 1.0);
    vec3 uv = distortShadow(clip.xyz / clip.w) * 0.5 + 0.5;
    if (any(lessThan(uv, vec3(0.001))) || any(greaterThan(uv, vec3(0.999)))) return 0.0;
    float bias = 0.04 * abs(shadowProjection[2][2]);
    return step(uv.z - bias, texture(shadowtex0, uv.xy).r);
}

// Cached per-source transmission is evaluated in the air outside this face.
// Reuse it for diffuse injection without tracing every lamp at every GI substep.
vec3 giLampIrradiance(ivec3 air, vec3 normal, vec3 receiver) {
    if (!lpvInside(air) || !lpvHeaderValid(texelFetch(colortex8, ivec2(0), 0))) return vec3(0.0);
    ivec2 address = lpvAddress(air);
    vec3 identities = texelFetch(colortex10, address, 0).rgb;
    vec3 light = vec3(0.0);
    for (int entry = 0; entry < 3; entry++) {
        int identity = int(round(identities[entry])) - 1;
        if (identity < 0) continue;
        ivec3 source = lpvCell(identity);
        uint material = lpvVoxel(source);
        if (lpvKind(material) != LPV_EMITTER) continue;
        vec3 ray = vec3(source) + vec3(0.5, 0.72, 0.5) - receiver;
        float distance = length(ray);
        float cosine = max(dot(normal, ray / max(distance, 0.001)), 0.0);
        vec3 colour = lpvColour(material);
#if ENABLE_COLOURED_LIGHTING == 0
        colour = vec3(1.0, 0.65, 0.32);
#endif
        vec3 transmission = texelFetch(colortex11,
            address + ivec2(0, entry * textureSize(colortex8, 0).y), 0).rgb;
        light += colour * colour * lpvSourceEnergy(distance, lpvEmission(material))
            * transmission * cosine;
    }
    return light;
}
#endif

void main() {
    result = vec4(0.0);
#if GI_QUALITY > 0
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    int height = textureSize(colortex8, 0).y;
    int face = pixel.y / height;
    int index = pixel.x + (pixel.y % height) * textureSize(colortex8, 0).x;
    if (index < LPV_HEADER_SIZE) {
        vec3 origin = vec3(lpvOrigin(cameraPosition));
        vec3 part = face == 0 ? floor(origin / 1048576.0)
            : face == 1 ? mod(floor(origin / 1024.0), 1024.0) : mod(origin, 1024.0);
        result = index == 0
            ? vec4(lpvShape().x, frameCounter % 1024, frameCounter / 1024, 1973.0)
            : vec4(part, 1.0);
        return;
    }
    if (face >= 6 || index - LPV_HEADER_SIZE >= lpvShape().x * lpvShape().y * lpvShape().z) return;
    ivec3 cell = lpvCell(index - LPV_HEADER_SIZE);
    ivec3 direction = giDirection(face);
    bool valid = giHistoryValid();
    ivec3 shift = valid ? lpvOrigin(cameraPosition) - giStoredOrigin() : ivec3(0);
    uint material = lpvVoxel(cell);
    if (lpvOpaque(material)) {
        ivec3 air = cell + direction;
        if (!lpvInside(air) || lpvOpaque(lpvVoxel(air))) return;
        vec3 normal = vec3(direction);
        vec3 receiver = vec3(cell) + 0.5 + normal * 0.51;
        vec3 world = receiver + vec3(lpvOrigin(cameraPosition));
        vec3 direct = giLampIrradiance(air, normal, receiver);
#if SIMPLE_DIMENSION == 0
        vec3 sun = getSunLightColor() + getMoonLightColor();
        vec3 lightDirection = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
        float cosine = max(dot(normal, lightDirection), 0.0);
        if (cosine > 0.001) direct += sun * cosine * giSunVisibility(world, normal);
        float sky = lpvKind(material) == LPV_SOLID ? lpvEmission(material) / 15.0 : 0.0;
        direct += mix(vec3(0.48, 0.64, 1.0), vec3(0.8, 0.88, 1.0), getDayFactor())
            * sky * sky * giSkyVisibility(air) * (0.05 + 0.25 * getDayFactor()) * AMBIENT_STRENGTH
            * (0.35 + 0.65 * max(normal.y, 0.0));
#endif
        vec3 incoming = vec3(0.0);
#if GI_MULTIBOUNCE == 1
        if (valid) {
            incoming = giRead(air, face ^ 1, shift) * 0.6;
            for (int side = 0; side < 6; side++) {
                if (side / 2 != face / 2) incoming += giRead(air, side, shift) * 0.1;
            }
        }
#endif
        vec3 albedo = lpvKind(material) == LPV_SOLID ? lpvColour(material) : vec3(0.45);
        result.rgb = min(albedo, vec3(0.85)) * (direct + incoming * GI_REFLECTANCE);
    } else if (valid) {
        // A narrow cone spreads low-frequency radiance over the four adjacent
        // lobes. Weights sum to one; air cannot create or reflect energy.
        ivec3 upstream = cell - direction;
        vec3 incoming = giRead(upstream, face, shift) * 0.68;
        if (!lpvOpaque(lpvVoxel(upstream))) {
            for (int side = 0; side < 6; side++) {
                if (side / 2 != face / 2) incoming += giRead(upstream, side, shift) * 0.08;
            }
        } else {
            incoming = giRead(upstream, face, shift);
        }
        if (lpvKind(material) == LPV_GLASS) incoming *= lpvColour(material) * lpvColour(material);
        result.rgb = incoming * 0.985;
    }
    result.rgb = clamp(result.rgb, vec3(0.0), vec3(8.0));
    result.a = float(lpvKind(material));
#endif
}
