/* A local, position-aware environment capture complements the screen image.
 * It stores observed scene radiance and position, not reconstructed block
 * occupancy. Camera-visible samples refresh it; off-screen observations follow
 * camera translation. The previous bank is immutable during a frame.
 */
#include "/lib/water_environment_layout.glsl"

struct WaterEnvironmentSample {
    vec3 point;
    vec3 colour;
    float travel;
};

bool waterEnvironmentHistoryValid() {
#if SIMPLE_DIMENSION != 0
    return false;
#else
    int previous = (frameCounter + 720719) % 720720;
    return frameCounter > 1 && length(cameraPosition - previousCameraPosition) < 8.0
        && imageLoad(colorimg5, ivec2(26 + (previous & 1), imageSize(colorimg5).y - 1)).r == uint(previous) + 1u;
#endif
}

WaterEnvironmentSample waterEnvironmentRead(ivec2 cell) {
    int bank = (frameCounter + 1) & 1;
    vec3 point = uintBitsToFloat(uvec3(
        imageLoad(colorimg5, waterEnvironmentAddress(cell, bank, 0)).r,
        imageLoad(colorimg5, waterEnvironmentAddress(cell, bank, 1)).r,
        imageLoad(colorimg5, waterEnvironmentAddress(cell, bank, 2)).r));
    vec4 rgbe = unpackUnorm4x8(imageLoad(colorimg5, waterEnvironmentAddress(cell, bank, 3)).r);
    float travel = uintBitsToFloat(imageLoad(colorimg5, waterEnvironmentAddress(cell, bank, 4)).r);
    return WaterEnvironmentSample(point, rgbe.rgb * exp2(round(rgbe.a * 255.0) - 128.0), travel);
}

ivec2 waterEnvironmentCell(vec3 direction) {
    return clamp(ivec2(waterEnvironmentUv(direction) * float(waterEnvironmentSide)),
        ivec2(0), ivec2(waterEnvironmentSide - 1));
}

void waterEnvironmentWrite(ivec2 cell, WaterEnvironmentSample value) {
    int bank = frameCounter & 1;
    float exponent = ceil(log2(max(max(value.colour.r, max(value.colour.g, value.colour.b)), 1e-8)));
    uint colour = packUnorm4x8(vec4(value.colour * exp2(-exponent), (exponent + 128.0) / 255.0));
    imageStore(colorimg5, waterEnvironmentAddress(cell, bank, 0), uvec4(floatBitsToUint(value.point.x)));
    imageStore(colorimg5, waterEnvironmentAddress(cell, bank, 1), uvec4(floatBitsToUint(value.point.y)));
    imageStore(colorimg5, waterEnvironmentAddress(cell, bank, 2), uvec4(floatBitsToUint(value.point.z)));
    imageStore(colorimg5, waterEnvironmentAddress(cell, bank, 3), uvec4(colour));
    imageStore(colorimg5, waterEnvironmentAddress(cell, bank, 4), uvec4(floatBitsToUint(value.travel)));
}

// The capture is an environment approximation, not an intersection with a
// guessed infinite plane. Use position to correct parallax and reject sources
// in front of the reflecting interface or on its submerged side.
vec4 sampleWaterEnvironment(vec3 viewOrigin, vec3 viewDirection, vec3 viewNormal) {
    if (!waterEnvironmentHistoryValid()) return vec4(0.0);
    vec3 origin = viewToWorld(viewOrigin) + cameraPosition - previousCameraPosition;
    vec3 ray = mat3(gbufferModelViewInverse) * viewDirection;
    vec3 normal = mat3(gbufferModelViewInverse) * viewNormal;
    vec3 lookup = ray;
    for (int i = 0; i < 2; ++i) {
        WaterEnvironmentSample sampleValue = waterEnvironmentRead(waterEnvironmentCell(lookup));
        if (sampleValue.point.x > 60000.0) break;
        float distance = dot(sampleValue.point - origin, ray);
        if (distance <= 0.05) break;
        lookup = normalize(origin + ray * distance);
    }
    vec2 pixel = waterEnvironmentUv(lookup) * float(waterEnvironmentSide) - 0.5;
    ivec2 base = ivec2(floor(pixel));
    vec2 fraction = fract(pixel);
    vec3 colour = vec3(0.0);
    float sum = 0.0;
    float distanceSum = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 cell = clamp(base + ivec2(x,y), ivec2(0), ivec2(waterEnvironmentSide - 1));
            WaterEnvironmentSample observation = waterEnvironmentRead(cell);
            if (observation.point.x > 60000.0 || observation.travel > 24.0) continue;
            vec3 relative = observation.point - origin;
            if (dot(relative, ray) <= 0.05 || dot(relative, normal) < -0.03) continue;
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                         * (y == 0 ? 1.0 - fraction.y : fraction.y);
            colour += observation.colour * weight;
            distanceSum += dot(relative, ray) * weight;
            sum += weight;
        }
    }
    return sum > 0.001 ? vec4(colour / sum, distanceSum / sum) : vec4(0.0);
}

#ifdef WATER_TRANSMISSION_PASS
void updateWaterEnvironment(ivec2 cell) {
    int bank = frameCounter & 1;
    if (all(equal(cell, ivec2(0))))
        imageStore(colorimg5, ivec2(26 + bank, imageSize(colorimg5).y - 1), uvec4(uint(frameCounter) + 1u));
    vec3 direction = waterEnvironmentDirection((vec2(cell) + 0.5) / float(waterEnvironmentSide));
    WaterEnvironmentSample result = WaterEnvironmentSample(vec3(65505.0), vec3(0.0), 0.0);
    vec3 view = mat3(gbufferModelView) * direction;
    if (view.z < -0.001) {
        vec4 clip = gbufferProjection * vec4(view, 0.0);
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)))) {
            ivec2 p = ivec2(uv * vec2(textureSize(depthtex1,0)));
            float depth = texelFetch(depthtex1,p,0).r;
            vec4 radiance = texelFetch(colortex6,p,0);
            if (depth >= 0.999999) {
                result.point = vec3(65504.0);
                waterEnvironmentWrite(cell,result);
                return;
            }
            vec2 centre = (vec2(p) + 0.5) / vec2(textureSize(depthtex1,0));
            vec3 point = screenToView(centre,depth);
            vec4 water = texelFetch(colortex9,p,0);
            if (length(point) > 1.0 && radiance.a > 1.0 && radiance.a < 4.5
                && (water.a < 0.5 || water.b >= -point.z)) {
                result.point = viewToWorld(point);
                result.colour = radiance.rgb;
                waterEnvironmentWrite(cell,result);
                return;
            }
        }
    }
    if (waterEnvironmentHistoryValid()) {
        vec3 delta = cameraPosition - previousCameraPosition;
        WaterEnvironmentSample old = waterEnvironmentRead(cell);
        if (old.point.x < 60000.0) {
            if (dot(delta,delta) > 0.000001)
                old = waterEnvironmentRead(waterEnvironmentCell(direction * length(old.point) + delta));
            old.point -= delta;
            old.travel += length(delta);
            if (old.point.x < 60000.0 && old.travel < 24.0 && length(old.point) < far * 1.4) result = old;
        }
    }
    waterEnvironmentWrite(cell,result);
}
#endif
