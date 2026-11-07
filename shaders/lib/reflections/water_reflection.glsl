// Water reflection.
#ifndef LIB_WATER_REFLECTION_GLSL
#define LIB_WATER_REFLECTION_GLSL

/* 水面光学与波浪工具。共享 Fresnel、八面体法线编码和连续波浪高度场。
 * 三组正弦分量使用绝对世界坐标保持区块接缝连续，正弦差公式直接求差分法线。
 */
#include "/lib/water/surface_data_composite.glsl"

/* Screen-space intersections against the immutable opaque depth layer.
 * Each sample is classified against the visible depth: in front, inside the
 * assumed object thickness, or deep behind. Entering the thickness band from
 * either side is refined by bisection. A local depth plane must then intersect
 * the ray inside its own pixel, so continuous surfaces give exact hits.
 * Reconstructing geometry from depth also works during translucent rendering,
 * when the normal attachment no longer describes this opaque depth layer.
 *
 * 深度缓冲只记录物体正面，不知道物体有多厚。参考 BSL 的厚度判断：
 *   - 光线进入可见表面后方一个物体厚度以内，视为打中该物体。
 *     连续表面用局部平面求出精确交点；轮廓像素和单像素的叶片、
 *     叶隙里露出的山体没有可用的切线，直接命中该像素（打进物体侧面）。
 *   - 光线从前景后方很深处穿过时不算命中；它之后可能从叶隙后方
 *     直接进入山体的厚度范围（深→内），同样会被细化并命中。
 *     旧版只检测前→后的穿越，透过树叶的倒影因此露出天空。
 *   - 前景挡住原本在光线后方的背景时，记住背景深度；光线在前景后方
 *     到达这个深度即命中背景（树叶、树干后方的山体），取背景的真实颜色。
 *   - 水面倒影裁掉水面以下的像素：河床既不会被打中，也不挡住光线。
 * 未命中时不猜测遮挡物：屏幕空间无法区分“在几何体后方”与“被几何体挡住”。
 * 旧版用压暗的轮廓颜色代替天空，倒影里出现大量细黑边。
 * 相机看不到的遮挡由 reflection_occlusion.glsl 用阴影贴图判断。
 * 命中距离没有远距离淡出：远处的山和树林也应出现在倒影里，而不是渐变成天空。
 */
#include "/lib/reflections/screen_geometry.glsl"

/* Adaptive screen reflection inspired by the refinement strategy used in BSL,
 * Complementary and Sildur. A candidate is refined by shortening the travelled
 * segment; thin alpha-tested surfaces need no unreliable depth-plane normal.
 */
#include "/lib/reflections/screen_reflection_adaptive.glsl"

/* Opaque reflection radiance is straight linear HDR at mip zero. Filtering
 * must validate each texel before reading colour; a filtered colour lookup can
 * already contain sky/foreground pixels that a later depth test cannot remove.
 */
#include "/lib/reflections/reflection_source.glsl"

/* A reflection source is surface radiance, without camera fog. Apply only the
 * reflected air segment here; the receiving surface applies its own segment.
 */
#include "/lib/reflections/reflection_medium.glsl"

/* 水面局部光照与 GGX 高光；只供片元阶段使用。 */
#include "/lib/water/water_lighting_water.glsl"

/* Water absorption and illuminated in-scattering shared by surface/underwater optics. */
#include "/lib/water/water_volume_water.glsl"

/* 柔和聚光与水下日照工具。变形胞元模拟聚光纹理，太阳折射方向决定投影；
 * 仅查询现有的不透明阴影图，不生成光子、光照贴图或额外场景数据。
 */
#include "/lib/water/water_effects_water.glsl"

/* 通用表面BRDF与反射权重。具体材质参数由资源包LabPBR贴图提供。 */
#include "/lib/surface/materials.glsl"

/* Low-frequency reflected radiance shared by forward shading and SSR.
 * A complete base radiance prevents another metal surface from appearing black
 * in the first reflection bounce, before the screen reflection pass runs.
 */
#include "/lib/surface/material_environment.glsl"

/* 透明方块颜色独立于水面保存。RGB 是预乘辐射，alpha 是累计覆盖率；
 * 水面阶段可把这层放在水体之前或之后，水下视角也能保留玻璃。
 */
#include "/lib/surface/transparency.glsl"

/* The camera and sun depth maps provide two views of the same geometry.
 * The sun view supplies alpha-tested albedo, normal and light levels for
 * visible shadow casters. Only a ray/surface intersection can return colour.
 */
uniform sampler2D shadowcolor1;
uniform sampler2D depthtex1;
#ifndef LUCULENT_WORLD_DEPTH_UNIFORM
#define LUCULENT_WORLD_DEPTH_UNIFORM
uniform sampler2D depthtex2;
#endif

#if ENABLE_COLOURED_LIGHTING == 0 && GI_QUALITY == 0
layout(r32ui, binding=5) uniform uimage2D colorimg5;
#endif
vec3 waterLightmapLevel(float level) {
    ivec2 p = ivec2(clamp(level, 0.0, 15.0), imageSize(colorimg5).y - 1);
    return toLinearSpace(unpackUnorm4x8(imageLoad(colorimg5, p).r).rgb);
}

vec3 waterShadowPoint(vec2 uv, float depth) {
    vec4 point = shadowProjectionInverse * vec4(undistortShadow(uv * 2.0 - 1.0),
        depth * 2.0 - 1.0, 1.0);
    return (shadowModelViewInverse * vec4(point.xyz / point.w, 1.0)).xyz;
}

vec3 waterShadowCoordinate(vec3 worldRelative) {
    vec4 projected = shadowProjection * shadowModelView * vec4(worldRelative, 1.0);
    return distortShadow(projected.xyz / projected.w) * 0.5 + 0.5;
}

// Decode native opaque samples independently of any water or glass in front.
uniform sampler2D colortex5;
#ifdef WATER_TRANSMISSION_PASS
#define WATER_NATIVE_GLASS
#endif
#include "/lib/water_native_faces.glsl"
#include "/lib/water_entity_triangles.glsl"

vec3 waterCasterRecord(ivec2 pixel) {
    vec3 record = texelFetch(shadowcolor1, pixel, 0).rgb;
    if (record.x < 0.0) record.z = -1.0 - record.z;
    record.xy = mix(record.xy, -1.0 - record.xy, lessThan(record.xy, vec2(0.0)));
    return record;
}

vec3 waterRecordNormal(vec3 record) {
    vec2 encoded = floor(record.xy / 65536.0);
    if (encoded.x < 255.0) return decodeNormal(encoded / vec2(254.0, 255.0));
    int code = int(encoded.y) & 7;
    vec3 normal = vec3(0.0);
    normal[code / 2] = (code & 1) == 0 ? 1.0 : -1.0;
    return normal;
}

bool waterCasterOwns(vec3 record, vec3 point, vec3 normal) {
    if (record.z < 0.0) {
        int triangle = int(mod(record.x, 65536.0)) - 1;
        return waterEntityContains(triangle, point);
    }
    vec2 label = floor(record.xy / 65536.0);
    if (label.x < 255.0) return true;
    ivec3 cell = ivec3(floor(point + cameraPosition - 0.004 * normal)) & 1;
    return (int(label.y) >> 3) == cell.x + 2 * cell.y + 4 * cell.z;
}

vec3 waterCasterNormal(vec2 uv) {
    return waterRecordNormal(waterCasterRecord(ivec2(uv * vec2(textureSize(shadowcolor1, 0)))));
}

vec3 waterCasterAlbedo(ivec2 pixel, vec3 record, vec3 normal, vec3 hit) {
    float attributes = record.z < 0.0 ? -1.0 - record.z : record.z;
    vec3 tint = mod(floor(attributes / vec3(1.0, 16.0, 256.0)), 16.0) / 15.0;
    if (texelFetch(shadowcolor1, pixel, 0).r < 0.0) return tint;
    ivec2 size = textureSize(shadowcolor1, 0);
    vec2 uv = mod(record.xy, 65536.0) / 65535.0;
    vec2 fraction = waterShadowCoordinate(hit).xy * vec2(size) - vec2(pixel) - 0.5;
    vec2 gradients[2];
    for (int axis = 0; axis < 2; ++axis) {
        ivec2 stride = axis == 0 ? ivec2(1, 0) : ivec2(0, 1);
        float best = 1e20;
        gradients[axis] = vec2(0.0);
        for (int side = -1; side <= 1; side += 2) {
            ivec2 tap = clamp(pixel + side * stride, ivec2(0), size - 1);
            vec3 neighbour = waterCasterRecord(tap);
            if (!waterCasterOwns(neighbour, hit, normal)
                || dot(normal, waterRecordNormal(neighbour)) < 0.96) continue;
            vec2 centre = (vec2(tap) + 0.5) / vec2(size);
            vec3 point = waterShadowPoint(centre, texelFetch(shadowtex1, tap, 0).r);
            if (abs(dot(point - hit, normal)) > 0.015) continue;
            vec2 delta = (mod(neighbour.xy, 65536.0) / 65535.0 - uv) * float(side);
            float cost = dot(delta, delta);
            if (cost < best) {
                gradients[axis] = delta;
                best = cost;
            }
        }
    }
    vec2 fine = uv + gradients[0] * fraction.x + gradients[1] * fraction.y;
    return tint * textureLod(colortex5, fine, 0.0).rgb;
}

// If the second view found a surface also seen by the camera, keep its full
// native material shading. A depth mismatch means an intervening object.
bool waterCameraSees(vec3 hit, sampler2D depths, out vec2 uv) {
    if (hit.z >= -near) return false;
    vec4 clip = gbufferProjection * vec4(hit, 1.0);
    uv = clip.xy / clip.w * 0.5 + 0.5;
    ivec2 size = textureSize(depths, 0);
    ivec2 pixel = ivec2(floor(uv * vec2(size)));
    if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))) return false;
    float depth = texelFetch(depths, pixel, 0).r;
    vec3 point = screenToView((vec2(pixel) + 0.5) / vec2(size), depth);
    return depth < 0.999999 && length(point - hit) < max(0.008, -hit.z * 2.0 / viewHeight);
}

bool waterCameraSees(vec3 hit, out vec2 uv) {
    return waterCameraSees(hit, depthtex2, uv);
}

// Shade one verified native texel. Both sides of the viewport boundary
// evaluate the same material, AO, lightmap and glass/water transmission.
vec4 waterCasterRadiance(vec2 bestUv, vec3 hitView) {
    ivec2 mapSize = textureSize(shadowcolor1, 0);
    ivec2 pixel = ivec2(bestUv * vec2(mapSize));
    vec3 record = waterCasterRecord(pixel);
    vec3 normal = waterRecordNormal(record);
    vec4 owned = waterOwnedColour(hitView, normal);
    if (owned.a > 0.0) return owned;
    vec3 albedo = toLinearSpace(waterCasterAlbedo(pixel, record, normal, viewToWorld(hitView)));
    float attributes = record.z < 0.0 ? -1.0 - record.z : record.z;
    float packedLight = floor(attributes / 65536.0);
    float ao = mod(floor(attributes / 4096.0), 16.0) / 15.0;
    vec2 levels = vec2(mod(packedLight, 16.0), floor(packedLight / 16.0));
    vec2 lm = (levels + 0.5) / 16.0;
    vec3 viewNormal = mat3(gbufferModelView) * normal;
    float front = textureLod(shadowtex0, bestUv, 0.0).r;
    float solid = textureLod(shadowtex1, bestUv, 0.0).r;
    vec3 transfer = vec3(1.0);
    if (shadowDepthToBlocks(solid - front) > 0.02) {
        vec4 cover = textureLod(shadowcolor0, bestUv, 0.0);
        transfer = abs(cover.a - 0.5) < 0.1 ? cover.rgb : vec3(0.0);
    }
    samplingWaterCaster = true;
    vec3 radiance = computeSurfaceLighting(albedo, viewNormal, lm, transfer, ao, hitView);
    samplingWaterCaster = false;
    return vec4(radiance, 1.0);
}

// Intersect planes observed by the sun, then reproject the proposed hit to
// validate actual geometry and texture coverage before shading that surface.
bool waterSunIntersection(vec3 originView, vec3 directionView, float maximum,
                          out float hitDistance, out vec2 bestUv) {
    hitDistance = -1.0;
    bestUv = vec2(-1.0);
#if ENABLE_SHADOWS == 1 && SIMPLE_DIMENSION == 0
    vec3 origin = viewToWorld(originView);
    vec3 ray = mat3(gbufferModelViewInverse) * directionView;
    float nearest = min(48.0, maximum);
    float range = nearest;
    for (int stepIndex = 0; stepIndex <= max(REFLECTION_OCCLUSION_STEPS, 6); ++stepIndex) {
        float u = float(stepIndex) / float(max(REFLECTION_OCCLUSION_STEPS, 6));
        float probeT = 0.03 + range * u * u;
        vec3 shadow = waterShadowCoordinate(origin + ray * probeT);
        if (any(lessThanEqual(shadow, vec3(0.0))) || any(greaterThanEqual(shadow, vec3(1.0)))) break;
        vec2 pixel = shadowTexelCenter(shadow.xy);
        float depth = textureLod(shadowtex1, pixel, 0.0).r;
        if (depth >= 0.999999) continue;
        vec3 plane = waterShadowPoint(pixel, depth);
        vec3 normal = waterCasterNormal(pixel);
        float cosine = dot(normal, ray);
        if (abs(cosine) < 0.015) continue;
        if (cosine > 0.0 && textureLod(shadowcolor1, pixel, 0.0).g >= 0.0) continue;
        float t = dot(plane - origin, normal) / cosine;
        vec3 proposedRecord = waterCasterRecord(ivec2(pixel * vec2(textureSize(shadowcolor1, 0))));
        if (proposedRecord.z < 0.0) {
            int triangle = int(mod(proposedRecord.x, 65536.0)) - 1;
            if (!waterEntityIntersection(triangle, origin, ray, t)) continue;
        }
        if (t <= 0.008 || t >= nearest) continue;
        vec3 hit = origin + ray * t;
        vec3 checkCoord = waterShadowCoordinate(hit);
        if (any(lessThanEqual(checkCoord, vec3(0.0))) || any(greaterThanEqual(checkCoord, vec3(1.0)))) continue;
        pixel = shadowTexelCenter(checkCoord.xy);
        depth = textureLod(shadowtex1, pixel, 0.0).r;
        if (depth >= 0.999999) continue;
        vec3 observed = waterShadowPoint(pixel, depth);
        vec3 observedRecord = waterCasterRecord(ivec2(pixel * vec2(textureSize(shadowcolor1, 0))));
        vec3 observedNormal = waterRecordNormal(observedRecord);
        if (!waterCasterOwns(observedRecord, hit, observedNormal)) continue;
        if (abs(dot(hit - observed, observedNormal)) > 0.018
            || length(hit - observed) > 0.35 || dot(normal, observedNormal) < 0.96) continue;
        nearest = t;
        bestUv = pixel;
    }
    if (bestUv.x >= 0.0) {
        hitDistance = nearest;
        return true;
    }
#endif
    return false;
}

/* 空气到水的折射。由水面法线和折射率确定一条 Snell 光线，再求水底取样位置。
 * 按原生表面方向求最近交点，在相邻平面的交线处积分像素覆盖。
 */
#include "/lib/water/water_refraction.glsl"

/* 世界坐标中的雨滴波环。四个邻域滴点使用解析斜率，避免纹理动画的平铺和跳帧。
 * 半径小于胞元的一半，四邻域足够覆盖；像素足迹过大时连续退出。
 */
#include "/lib/weather/rain_ripples.glsl"

uniform sampler2D colortex9;
uniform sampler2D depthtex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;

// 水的 Fresnel。物理上的 Schlick 曲线（F0 = 0.02，五次方）在常见的俯视角下
// 几乎不反射，水面因此被水色主导。这里参考 Sildur 的做法：略高的 F0 与四次方
// 曲线，使中等角度也能看到明显的天空和景物倒影；粗糙水面在掠射时略降低峰值。
float waterFresnel(float cosine, float roughness) {
    float f0 = 0.05;
    float grazing = max(1.0 - roughness * 0.6, f0);
    return f0 + (grazing - f0) * pow4(1.0 - clamp(cosine, 0.0, 1.0));
}

// 天空回退保留同一套天空/云输入；封闭水域的天空辐射为零。
vec3 waterEnvironment(vec3 originWorld, vec3 rayWorld, float skyVisibility, bool celestial) {
#if SIMPLE_DIMENSION == 1
    return mix(dimensionAmbient(rayWorld) * AMBIENT_STRENGTH,
               skyAtmosphereRadiance(rayWorld) * 1.8, END_ATMOSPHERE * 0.65);
#elif SIMPLE_DIMENSION == -1
    return dimensionAmbient(rayWorld) * AMBIENT_STRENGTH;
#endif
    if (skyVisibility <= 0.001) {
        return vec3(0.0);
    }
    vec3 sky = skyAtmosphereRadiance(rayWorld) + skyStars(rayWorld);
    if (celestial) {
        sky += skyCelestialRadiance(rayWorld);
    }
#if WATER_REFLECTION_CLOUDS == 1
    // The sky strip already integrates clouds from the eye. Only integrate
    // them again when the reflected ray origin produces discernible parallax.
    float cloudRange = max(abs(CLOUD_HEIGHT - originWorld.y), 1.0) / max(rayWorld.y, 0.001);
    float parallax = length(originWorld - cameraPosition) / cloudRange;
    float detail = smoothstep(0.012, 0.035, parallax);
    vec4 cloud = cloudEnvironment(rayWorld);
    if (detail > 0.0) cloud = mix(cloud, traceVolumetricCloudsFrom(originWorld, rayWorld, CLOUD_DISTANCE, true), detail);
#else
    vec4 cloud = cloudEnvironment(rayWorld);
#endif
    return (cloud.rgb + sky * (1.0 - cloud.a)) * skyVisibility;
}

// Reproject only the footprint of an already resolved visible receiver. The
// full two-view search is shared by these samples. At a crease each subray
// can choose the neighbouring face, but cannot borrow an unrelated backdrop.
vec3 waterBedCoverage(vec2 uv, vec3 position, vec3 opticalNormal, vec3 bed,
                      vec3 normal, vec3 centreColour, float height) {
    const vec2 pattern[4] = vec2[4](vec2(-0.375, -0.125), vec2(0.125, -0.375),
        vec2(0.375, 0.125), vec2(-0.125, 0.375));
    vec2 size = vec2(viewWidth, viewHeight);
    float eta = 1.0 / mix(1.0, WATER_IOR, WATER_REFRACTION_STRENGTH);
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 pixelUv = uv + pattern[i] / size;
        vec3 eye = normalize(screenToView(pixelUv, 0.5));
        float incidence = dot(eye, opticalNormal);
        if (abs(incidence) < 0.01) { sum += centreColour; continue; }
        vec3 entry = eye * (dot(position, opticalNormal) / incidence);
        vec3 ray = refract(eye, opticalNormal, eta);
        float slope = dot(ray, normal);
        if (abs(slope) < 0.001) { sum += centreColour; continue; }
        float t = dot(bed - entry, normal) / slope;
        vec3 sampleHit = entry + t * ray;
        vec2 projected = waterProjectPixel(sampleHit, size);
        ivec2 cell = ivec2(floor(projected));
        if (t <= 0.0 || any(lessThan(cell, ivec2(0))) || any(greaterThanEqual(cell, ivec2(size)))) {
            sum += centreColour;
            continue;
        }
        vec2 source = (vec2(cell) + 0.5) / size;
        float depth = texelFetch(depthtex2, cell, 0).r;
        if (depth >= 0.999999) { sum += centreColour; continue; }
        vec3 point = screenToView(source, depth);
        float tag = texelFetch(colortex6, cell, 0).a;
        vec3 face = mat3(gbufferModelView) * waterBedNormal(source, point, depthtex2);
        int crease = int(round(fract(tag) * 256.0)) & 15;
        if (crease != 0) {
            WaterRayHit hit = waterCreaseHit(cell, point, face, crease, entry, ray, 48.0, depthtex2, size);
            if (hit.distance <= 0.0) { sum += centreColour; continue; }
            sampleHit = entry + ray * hit.distance;
            projected = hit.uv * size;
            source = waterBedUv(hit.uv);
            point = screenToView(source, textureLod(depthtex2, source, 0.0).r);
        } else if (abs(dot(point - bed, normal)) > max(0.008, -point.z * 0.0006)) {
            sum += centreColour;
            continue;
        }
        bool unused;
        vec3 worldNormal = waterBedNormal(source, point, depthtex2);
        sum += waterTransmissionColor(colortex6, depthtex2, projected / size,
            viewToAbsoluteWorld(sampleHit), worldNormal, height, centreColour, unused);
    }
    return sum * 0.25;
}

// Cross the last few camera texels using radiance from the same 3D point.
// Reject a different face, a different block, or any intervening caster.
vec3 waterViewportColour(vec3 colour, vec2 uv, vec3 hitView, vec3 normalWorld) {
#if ENABLE_SHADOWS == 1 && SIMPLE_DIMENSION == 0
    vec2 margin = min(uv, 1.0 - uv) * vec2(viewWidth, viewHeight);
    float width = min(margin.x, margin.y);
    if (width >= 12.0) return colour;
    vec3 hit = viewToWorld(hitView);
    vec3 coord = waterShadowCoordinate(hit);
    if (any(lessThanEqual(coord, vec3(0.0))) || any(greaterThanEqual(coord, vec3(1.0)))) return colour;
    vec2 texel = shadowTexelCenter(coord.xy);
    float depth = textureLod(shadowtex1, texel, 0.0).r;
    if (depth >= 0.999999) return colour;
    vec3 surface = waterShadowPoint(texel, depth);
    vec3 normal = waterCasterNormal(texel);
    vec3 offset = cameraPosition - normal * 0.01;
    if (dot(normal, normalWorld) < 0.99 || abs(dot(surface - hit, normal)) > 0.012
        || any(notEqual(floor(surface + offset), floor(hit + offset)))) return colour;
    return mix(waterCasterRadiance(texel, hitView).rgb, colour, smoothstep(0.5, 12.0, width));
#else
    return colour;
#endif
}

// A tagged floor and a neighbouring riser can share a camera pixel. Compare
// block bounds along the face, allowing independent depth rounding along its normal.
bool waterSharesFaceBlock(vec3 centreWorld, vec3 hitWorld, vec3 axis) {
    vec3 separation = abs(floor(hitWorld) - floor(centreWorld));
    return all(lessThan(separation * (1.0 - abs(axis)), vec3(0.5)));
}

// A camera plane can extend across a seam if adjacent depth samples confirm it.
// When there is no support, another view may search beyond the apparent edge.
bool waterCameraHitSupported(WaterRayHit bed, vec3 position, vec3 ray, sampler2D depths, bool preHand) {
    if (bed.distance <= 0.0) return false;
    vec2 size = vec2(textureSize(depths, 0));
    vec2 uv = waterBedUv(bed.uv);
    ivec2 pixel = ivec2(uv * size);
    float depth = texelFetch(depths, pixel, 0).r;
    if (preHand && depth != texelFetch(depthtex1, pixel, 0).r) return true;
    float tag = texelFetch(colortex6, pixel, 0).a;
    if (tag >= 2.5 || fract(tag) < 0.0625 || fract(tag) >= 0.4375) return true;

    vec3 axis = waterAxisNormal(tag);
    vec3 normal = mat3(gbufferModelView) * axis;
    vec3 centre = screenToView(uv, depth);
    vec3 hit = position + ray * bed.distance;
    float tolerance = max(0.003, -hit.z * 0.0002);
    if (abs(dot(hit - centre, normal)) > tolerance) return false;
    vec3 hitWorld = viewToAbsoluteWorld(hit);
    if (waterSharesFaceBlock(viewToAbsoluteWorld(centre), hitWorld, axis)) return true;

    ivec2 base = ivec2(floor(waterProjectPixel(hit, size) - 0.5));
    bool continuous = true;
    for (int i = 0; i < 4; ++i) {
        ivec2 tap = clamp(base + ivec2(i & 1, i >> 1), ivec2(0), ivec2(size) - 1);
        float other = texelFetch(colortex6, tap, 0).a;
        float depth = texelFetch(depths, tap, 0).r;
        if (preHand && depth != texelFetch(depthtex1, tap, 0).r) other = 0.0;
        vec3 point = screenToView((vec2(tap) + 0.5) / size, depth);
        bool same = depth < 0.999999 && other < 2.5
            && int(fract(other) * 16.0) == int(fract(tag) * 16.0)
            && abs(dot(point - centre, normal)) < tolerance;
        if (same && waterSharesFaceBlock(viewToAbsoluteWorld(point), hitWorld, axis)) return true;
        continuous = continuous && same;
    }
    return continuous;
}

// Reuse the camera's native lighting only on the face found by the second view.
bool waterCameraSeesBed(vec3 hit, vec3 normalWorld, out vec2 uv) {
    if (!waterCameraSees(hit, uv)) return false;
    ivec2 pixel = ivec2(uv * vec2(textureSize(depthtex2, 0)));
    float face = fract(texelFetch(colortex6, pixel, 0).a);
    if (face < 0.0625 || face >= 0.4375) return true;
    vec3 axis = waterAxisNormal(face);
    if (dot(axis, normalWorld) < 0.99) return false;
    vec3 samplePoint = screenToView(waterBedUv(uv), texelFetch(depthtex2, pixel, 0).r);
    return waterSharesFaceBlock(viewToAbsoluteWorld(samplePoint), viewToAbsoluteWorld(hit), axis);
}

#include "/lib/water_bed_coverage.glsl"

// Resolve one covered point of the interface. Extra samples at a crease
// independently trace and shade their first hits; coordinates never blend.
vec3 transmitWaterSample(vec2 uv, vec3 position, vec3 opticalNormal, vec4 surface,
                         vec4 scattering, out float faceTag) {
    faceTag = 0.0;
    bool edge;
    vec3 originWorld = viewToAbsoluteWorld(position);
    vec3 incident = normalize(position);
    float opaqueDepth = texelFetch(depthtex2, ivec2(uv * vec2(viewWidth, viewHeight)), 0).r;
    vec3 opaquePosition = screenToView(waterBedUv(uv), min(opaqueDepth, 0.99999));
    vec3 opaqueWorld = viewToAbsoluteWorld(opaquePosition);
    vec3 receiverNormal;
    // Interpolate the interface index for the strength control; every enabled
    // setting still follows one continuous ray through real scene depth.
    vec3 ray = refract(incident, opticalNormal,
        1.0 / mix(1.0, WATER_IOR, WATER_REFRACTION_STRENGTH));
    WaterRayHit bedHit = WaterRayHit(uv, length(opaquePosition - position), false);
    vec4 alternateBed = vec4(0.0);
    float alternateDistance = -1.0;
    vec3 alternateNormal = vec3(0.0);
    bool approximate = false;
    if (WATER_REFRACTION_STRENGTH > 0.0) {
        bedHit = traceWaterGeometry(uv, position, ray, 48.0, depthtex2);
        bool supported = waterCameraHitSupported(bedHit, position, ray, depthtex2, false);
        if (!supported || bedHit.hidden) {
            // Include the visible boundary itself: a real face can precede
            // that sample by only a few millimetres at a step or corner.
            float extent = supported ? bedHit.distance : 48.0;
            vec2 sunPixel;
            bool sunHit = waterSunIntersection(position, ray, extent, alternateDistance, sunPixel);
            float faceDistance;
            float faceLimit = sunHit ? alternateDistance + 0.015 : extent;
            vec3 faceNormal;
            WaterFaceHit material;
            bool nativeHit = waterNearFaceHit(position, ray, faceLimit, faceDistance, faceNormal, material);
            if (nativeHit || sunHit) {
                if (nativeHit) alternateDistance = faceDistance;
                alternateNormal = nativeHit ? faceNormal : waterCasterNormal(sunPixel);
                vec3 point = position + ray * alternateDistance;
                vec2 witness;
                if (waterCameraSeesBed(point, alternateNormal, witness)) {
                    bedHit = WaterRayHit(witness, alternateDistance, false);
                } else if (nativeHit) {
                    alternateBed = vec4(waterLightFace(material, faceNormal, point), 1.0);
                } else {
                    alternateBed = waterCasterRadiance(sunPixel, point);
                }
            }
        }
        if (alternateBed.a <= 0.0 && bedHit.distance < 0.0 && opaqueDepth < 0.999999) {
            receiverNormal = waterBedNormal(uv, opaquePosition, depthtex2);
            approximate = true;
            bedHit = waterMissingReceiver(uv, position, ray, opaquePosition,
                mat3(gbufferModelView) * receiverNormal, depthtex2);
        }
    }
    float waterDistance = alternateDistance;
    vec3 transmitted = alternateBed.rgb;
    if (alternateBed.a > 0.0) {
        opaqueWorld = viewToAbsoluteWorld(position + ray * alternateDistance);
        receiverNormal = alternateNormal;
        faceTag = waterBedFaceTag(opaqueWorld, receiverNormal, waterDistance);
    } else {
        waterDistance = bedHit.distance >= 0.0 ? min(bedHit.distance, 48.0) : 48.0;
        vec2 transmittedUv = bedHit.uv;
        vec2 sourceUv = waterBedUv(transmittedUv);
        opaqueDepth = texture(depthtex2, sourceUv).r;
        opaquePosition = screenToView(sourceUv, min(opaqueDepth, 0.99999));
        opaqueWorld = viewToAbsoluteWorld(opaquePosition);
        receiverNormal = waterBedNormal(sourceUv, opaquePosition, depthtex2);
        // 水后的玻璃等与水底使用同一折射坐标；岸上的前景层继续由主像素合成。
        vec4 backgroundLayer = waterScreenLayer(sourceUv);
        vec4 sourceWater = waterSurfaceAtPixel(colortex9, ivec2(sourceUv * vec2(viewWidth, viewHeight)));
        float sourceDepth = -screenToView(sourceUv, texture(depthtex0, sourceUv).r).z;
        if (transparentLayerInFront(sourceDepth, sourceWater.a, backgroundLayer.a)) {
            backgroundLayer = vec4(0.0);
        }
        vec3 colourPoint = !approximate && bedHit.distance > 0.0
            ? viewToAbsoluteWorld(position + ray * bedHit.distance) : opaqueWorld;
        if (!approximate && backgroundLayer.a <= 0.0 && opaqueDepth < 0.999999
            && texelFetch(colortex6, ivec2(sourceUv * vec2(viewWidth, viewHeight)), 0).a < 2.5
            && fract(texelFetch(colortex6, ivec2(sourceUv * vec2(viewWidth, viewHeight)), 0).a) != 0.5) {
            faceTag = waterBedFaceTag(colourPoint, receiverNormal, waterDistance);
        }
        vec3 bedColour = waterTransmissionColor(colortex6, depthtex2, transmittedUv,
            colourPoint, receiverNormal, originWorld.y, scattering.rgb, edge);
        vec3 grid = abs(fract(opaqueWorld + 0.5) - 0.5);
        vec3 axis = abs(receiverNormal);
        float seam = axis.y > 0.99 ? min(grid.x, grid.z)
            : (axis.x > 0.99 ? min(grid.y, grid.z) : min(grid.x, grid.y));
        float radius = min(0.035, -opaquePosition.z * abs(gbufferProjectionInverse[1][1]) / viewHeight);
        bool boundary = edge || (max(axis.x, max(axis.y, axis.z)) > 0.99 && seam < radius);
        if (WATER_REFRACTION_STRENGTH > 0.0 && faceTag == 0.0 && boundary && waterDistance < 24.0) {
            bedColour = waterBedCoverage(uv, position, opticalNormal, opaquePosition,
                mat3(gbufferModelView) * receiverNormal, bedColour, originWorld.y);
        }
        if (WATER_REFRACTION_STRENGTH > 0.0 && !approximate && bedHit.distance > 0.0) {
            bedColour = waterViewportColour(bedColour, transmittedUv, position + ray * bedHit.distance, receiverNormal);
        }
        transmitted = applyTransparentLayer(bedColour, backgroundLayer);
        opaqueWorld = colourPoint;
        if (opaqueDepth >= 0.999999) receiverNormal = vec3(0.0);
    }
    float verticalDepth = max(originWorld.y - opaqueWorld.y, 0.0);
    // Keep the caustic field continuous as the same bed leaves the camera
    // view. A missing receiver has no illuminated surface to focus light on.
    transmitted *= waterCausticGain(opaqueWorld, receiverNormal, originWorld.y, surface.b);

    // 水上观察时增加随光程累积的散射遮蔽，浅水保留水底，深水以水色为主。
    // 此密度只用于水面合成，避免同时缩短水下相机的可见距离。
    vec3 extinction = waterExtinctionCoefficient() + vec3(WATER_SURFACE_OPACITY * 3.0);
    vec3 transmittance = exp(-extinction * waterDistance);
    transmitted *= transmittance;
    // 遮蔽水底的部分由受光水色补足，不再额外折半，避免不透明深水趋近蓝黑。
    transmitted += scattering.rgb * (1.0 - transmittance);
    // 浅水薄层逐渐变透明，使近岸与水底细节自然显现。
    float surfaceOpacity = imageLoad(colorimg1, ivec2(gl_FragCoord.xy)).g * smoothstep(0.0, 1.5, verticalDepth);
    transmitted = mix(transmitted, scattering.rgb, surfaceOpacity);

    return transmitted;
}

vec3 waterInterfaceNormal(vec3 position, vec3 originWorld, float sky) {
    // 透射采用实际位移高度场的斜率；放大的微表面高光法线不代表一整段水柱的几何。
    // 水底变浅与波浪偏折均来自下方同一次 Snell 求解，不额外变换水底深度。
    vec3 opticalNormal = vec3(0.0, 1.0, 0.0);
#if ENABLE_WATER_WAVES == 1
    float pixelAngle = 2.0 * abs(gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0);
    float resolved = waterResolvedWave(length(position), originWorld.y - cameraPosition.y, pixelAngle);
    opticalNormal = normalize(mix(opticalNormal, getWaterWaveNormal(originWorld.xz, frameTimeCounter), resolved));
#endif
    float footprint = 2.0 * abs(gbufferProjectionInverse[1][1]) * length(position)
        / (max(viewHeight, 1.0) * max(abs(dot(normalize(position),
            mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0))), 0.1));
    vec2 rainSlope = rainRippleSlope(originWorld.xz, frameTimeCounter, max(footprint, 0.055))
        * smoothstep(0.95, 0.995, sky);
    return mat3(gbufferModelView)
        * normalize(opticalNormal + vec3(-rainSlope.x, 0.0, -rainSlope.y));
}

uniform sampler2D colortex15;
#include "/lib/water_distant.glsl"
#include "/lib/reflections/bsl_water_reflection.glsl"

// 折射改变水底的投影位置；吸收仍由采样处的真实水内距离决定。
vec3 applyWaterReflection(vec3 color, vec2 uv, float normalVariance) {
    vec4 surface = waterSurfaceAtPixel(colortex9, ivec2(gl_FragCoord.xy));
    if (surface.a <= 0.001 || isEyeInWater != 0) {
        return color;
    }
    vec3 position = waterSurfacePosition(uv, surface.a);
    vec3 normal = decodeWaterNormal(surface.xy);
    vec3 incident = normalize(position);
    vec3 originWorld = viewToAbsoluteWorld(position);

    vec3 opticalNormal = waterInterfaceNormal(position, originWorld, surface.b);
    vec4 bed = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0);
    float lod = distantWaterBlend(position);
    vec3 farBed = vec3(0.0);
    if (lod > 0.0 && !readDistantBed(position, farBed)) lod = 0.0;
    vec3 transmitted = farBed;
    if (lod < 1.0) transmitted = mix(waterResolveBed(uv, position, opticalNormal, bed), farBed, lod);
    vec3 reflected = vec3(0.0);
    float roughness = sqrt(sqrt(pow4(WATER_ROUGHNESS) + min(2.0 * normalVariance, 0.035)));
    float coherence = 1.0 / (1.0 + roughness);
    // 水下窗口需要清晰的波浪起伏；水上倒影使用更平缓的光学斜率，
    // 避免同一组放大法线把相邻倒影拉成相互交叠的碎片。
    vec3 reflectionNormal = waterMirrorNormal(position, opticalNormal, normal, distantWaterBlend(position));
    float weight = bslWaterFresnel(dot(reflectionNormal, -incident))
        * WATER_REFLECTION_STRENGTH;
    if (weight > 0.001) {
        reflected = texelFetch(colortex15, ivec2(gl_FragCoord.xy), 0).rgb;
        reflected *= WATER_REFLECTION_BRIGHTNESS;
    }
    // 倒影直接与透射混合：夜晚、雨天的天空暗而灰，水面也随之变暗、变灰。
    vec3 result = mix(transmitted, reflected, weight);

    vec4 shadowClip = shadowProjection * shadowModelView * gbufferModelViewInverse * vec4(position, 1.0);
    float directSky = smoothstep(0.80, 0.99, surface.b);
    if (directSky > 0.001 && WATER_REFLECTION_STRENGTH * WATER_SPECULAR_STRENGTH > 0.0) {
        float directVisibility = waterOpaqueShadow(shadowClip, normal, length(position)) * directSky;
        directVisibility *= cloudProjectedShadow(originWorld,
            normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
        // 随机噪声法线的高频成分比正弦多，高光下限略放宽，避免远处一片细碎白点。
        float glintRoughness = sqrt(sqrt(pow4(max(WATER_ROUGHNESS * 0.6, 0.15))
                                       + min(2.0 * normalVariance, 0.035)));
        result += waterDirectSpecular(normal, position, glintRoughness) * directVisibility
                * WATER_REFLECTION_STRENGTH * WATER_SPECULAR_STRENGTH * coherence;
    }
    result = applyFog(result, length(position));
    return result;
}

#endif
