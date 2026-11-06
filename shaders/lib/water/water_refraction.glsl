// Water refraction.
#ifndef LIB_WATER_REFRACTION_GLSL
#define LIB_WATER_REFRACTION_GLSL

// 深度属于离散像素；法线、位置与颜色必须使用同一像素中心。
vec2 waterBedUv(vec2 uv) {
    vec2 size = vec2(viewWidth, viewHeight);
    return (clamp(floor(uv * size), vec2(0.0), size - 1.0) + 0.5) / size;
}

// 同一表面的单侧差分避免岸壁深度跳变把水底法线拉向屏外前景。
vec3 waterBedPoint(vec2 pixel, sampler2D opaqueDepth) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 uv = (clamp(pixel, vec2(0.0), size - 1.0) + 0.5) / size;
    float depth = texture(opaqueDepth, uv).r;
    return screenToView(uv, min(depth, 0.99999));
}

uniform sampler2D colortex6;

// Axis labels originate on the native primitive. Keep depth reconstruction
// for unlabelled surfaces (entities, oblique models and irregular foliage).
vec3 waterAxisNormal(float tag) {
    int code = int(fract(tag) * 16.0);
    if (code <= 2) return vec3(code == 1 ? 1.0 : -1.0, 0.0, 0.0);
    if (code <= 4) return vec3(0.0, code == 3 ? 1.0 : -1.0, 0.0);
    return vec3(0.0, 0.0, code == 5 ? 1.0 : -1.0);
}

vec3 waterNormalFromSample(vec2 uv, vec3 centre, sampler2D opaqueDepth, float tag) {
    vec2 pixel = floor(uv * vec2(viewWidth, viewHeight));
    if (fract(tag) == 0.5) return normalize(mat3(gbufferModelViewInverse) * vec3(0.0, 0.0, 1.0));
    if (fract(tag) >= 0.0625 && fract(tag) < 0.4375) return waterAxisNormal(tag);
    vec3 left = waterBedPoint(pixel - vec2(1.0, 0.0), opaqueDepth);
    vec3 right = waterBedPoint(pixel + vec2(1.0, 0.0), opaqueDepth);
    vec3 down = waterBedPoint(pixel - vec2(0.0, 1.0), opaqueDepth);
    vec3 up = waterBedPoint(pixel + vec2(0.0, 1.0), opaqueDepth);
    vec3 dx = abs(left.z - centre.z) < abs(right.z - centre.z) ? centre - left : right - centre;
    vec3 dy = abs(down.z - centre.z) < abs(up.z - centre.z) ? centre - down : up - centre;
    vec3 fallback = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 normal = safeNormalize(cross(dx, dy), fallback);
    normal *= dot(normal, -centre) >= 0.0 ? 1.0 : -1.0;
    return normalize(mat3(gbufferModelViewInverse) * normal);
}

vec3 waterBedNormal(vec2 uv, vec3 centre, sampler2D opaqueDepth) {
    ivec2 pixel = ivec2(uv * vec2(viewWidth, viewHeight));
    return waterNormalFromSample(uv, centre, opaqueDepth, texelFetch(colortex6, pixel, 0).a);
}

// 先检查每个颜色纹素的几何，再插值；天空黑底、岸上前景与异面颜色不混入水底。
vec3 waterTransmissionColor(sampler2D scene, sampler2D opaqueDepth, vec2 uv,
                            vec3 bedWorld, vec3 bedNormal, float waterHeight,
                            vec3 fallback, out bool edge) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 pixel = uv * size - 0.5;
    vec2 base = floor(pixel);
    vec2 fraction = fract(pixel);
    vec3 sum = vec3(0.0);
    float total = 0.0;
    float tolerance = max(0.02, length(bedWorld - cameraPosition) * 0.002);
    float faceData = fract(texelFetch(scene, ivec2(floor(uv * size)), 0).a);
    int centreTag = int(faceData * 16.0);
    bool axisTagged = centreTag >= 1 && centreTag <= 6;
    vec3 owner = floor(bedWorld - 0.005 * bedNormal);
    for (int x = 0; x < 2; x++) {
        for (int y = 0; y < 2; y++) {
            vec2 cell = clamp(base + vec2(float(x), float(y)), vec2(0.0), size - 1.0);
            vec2 sampleUv = (cell + 0.5) / size;
            float depth = texture(opaqueDepth, sampleUv).r;
            if (depth >= 0.999999) continue;
            vec4 colour = texelFetch(scene, ivec2(cell), 0);
            int neighbourTag = int(fract(colour.a) * 16.0);
            if (centreTag > 0 && neighbourTag > 0 && centreTag != neighbourTag) continue;
            vec3 world = viewToAbsoluteWorld(screenToView(sampleUv, depth));
            if (axisTagged && any(notEqual(floor(world - 0.005 * bedNormal), owner))) continue;
            if (world.y >= waterHeight - 0.005 || abs(dot(world - bedWorld, bedNormal)) > tolerance) continue;
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                * (y == 0 ? 1.0 - fraction.y : fraction.y);
            sum += colour.rgb * weight;
            total += weight;
        }
    }
    edge = total < 0.999 || (int(round(faceData * 256.0)) & 15) != 0;
    if (total > 0.00001) return sum / total;
    if (axisTagged) {
        vec4 owned = waterOwnedColour((gbufferModelView * vec4(bedWorld-cameraPosition,1.0)).xyz, bedNormal);
        if (owned.a > 0.0) return owned.rgb;
    }
    return fallback;
}

uniform sampler2D colortex7;
#include "/lib/water_ray.glsl"
#endif
