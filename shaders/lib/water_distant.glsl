/* Distant transmission shares one refracted ray per screen tile.
 * C7 contains the shaded bed. Above water C15 is free after the opaque pass;
 * its water depth identifies samples on the same interface.
 */
#if WATER_REFLECTION_STEPS >= 32
const int distantWaterStride = 2;
#else
const int distantWaterStride = 3;
#endif

float distantWaterBlend(vec3 position) {
    float range = length(position);
    float height = dot(position, mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));
    float pixelAngle = 2.0 * abs(gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0);
    float unresolved = 1.0 - waterResolvedWave(range, height, pixelAngle);
    return max(smoothstep(20.0, 38.0, range), unresolved * smoothstep(8.0, 16.0, range));
}

ivec2 distantWaterAnchor(ivec2 tile, ivec2 last) {
    return min(tile * distantWaterStride + distantWaterStride / 2, last);
}

// A thin strip of water with no representative retains its own detailed rays.
bool distantWaterSupports(ivec2 pixel, vec3 centre) {
    vec4 surface = texelFetch(colortex9, pixel, 0);
    if (surface.a < 0.5) return false;
    vec2 uv = (vec2(pixel) + 0.5) / vec2(textureSize(colortex9, 0));
    vec3 position = waterSurfacePosition(uv, surface.b);
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    return abs(dot(position - centre, up)) < 0.15 && distantWaterBlend(position) > 0.0;
}

// Broad crests steer the distant image. Keep its outgoing ray in the air
// hemisphere when the eye is almost level with a crest.
vec3 waterAirDirection(vec3 position, vec3 opticalNormal) {
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 incident = normalize(position);
    vec3 ray = reflect(incident, opticalNormal);
    float elevation = max(0.0, -dot(up, incident) * 0.25);
    return normalize(ray + up * max(elevation - dot(up, ray), 0.0));
}

#include "/lib/water/mirror_normal.glsl"

// Air-side appearance has its own BSL wave field; the displaced Snell
// interface and all distant transmission helpers below retain their inputs.


// One Snell ray meets a local bed-height estimate, then samples a real opaque
// texel. The straight camera sample supplies a fallback at disocclusions.
vec3 distantWaterBed(vec2 uv, vec3 position, vec3 normal, vec3 scatter) {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex1, pixel, 0).r;
    if (depth >= 0.999999) return scatter;
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 bed = screenToView(uv, depth);
    vec3 ray = refract(normalize(position), normal, 1.0 / mix(1.0, WATER_IOR, WATER_REFRACTION_STRENGTH));
    float column = max(dot(position - bed, up), 0.0);
    float travel = min(column / max(-dot(ray, up), 0.015), 48.0);
    vec3 target = position + ray * travel;
    vec2 size = vec2(textureSize(depthtex1, 0));
    if (target.z < -near) {
        vec2 projected = waterProjectPixel(target, size);
        if (all(greaterThanEqual(projected, vec2(0.0))) && all(lessThan(projected, size))) {
            ivec2 tap = ivec2(projected);
            vec2 tapUv = (vec2(tap) + 0.5) / size;
            float observedDepth = texelFetch(depthtex1, tap, 0).r;
            vec3 observed = screenToView(tapUv, min(observedDepth, 0.99999));
            if (observedDepth < 0.999999 && dot(position - observed, up) >= 0.0
                && abs(dot(observed - target, up)) < max(0.25, column * 0.2)) pixel = tap;
        }
    }
    vec3 attenuation = exp(-(waterExtinctionCoefficient() + vec3(WATER_SURFACE_OPACITY * 3.0)) * travel);
    vec3 colour = texelFetch(colortex6, pixel, 0).rgb;
    vec2 source = (vec2(pixel) + 0.5) / size;
    vec4 layer = waterScreenLayer(source);
    if (layer.a > 0.001) {
        vec3 front = screenToView(source, texelFetch(depthtex0, pixel, 0).r);
        if (dot(front - position, up) < 0.0) colour = applyTransparentLayer(colour, layer);
    }
    return mix(scatter, colour, attenuation);
}

// Only transmission is reconstructed from the coarse tile. The reflected
// scene is always queried on the current pixel's own ray.
bool readDistantBed(vec3 centre, out vec3 bed) {
    ivec2 last = textureSize(colortex15, 0) - 1;
    ivec2 tile = ivec2(gl_FragCoord.xy) / distantWaterStride;
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    float sum = 0.0;
    bed = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            ivec2 cell = tile + ivec2(x, y);
            if (any(lessThan(cell, ivec2(0))) || any(greaterThan(cell, last / distantWaterStride))) continue;
            ivec2 pixel = distantWaterAnchor(cell, last);
            vec4 surface = texelFetch(colortex9, pixel, 0);
            if (surface.a < 0.5) continue;
            float depth = surface.b;
            vec2 uv = (vec2(pixel) + 0.5) / vec2(last + 1);
            vec3 position = waterSurfacePosition(uv, depth);
            if (abs(dot(position - centre, up)) > 0.16 + depth * 0.0005) continue;
            vec2 delta = abs(vec2(pixel) + 0.5 - gl_FragCoord.xy) / float(distantWaterStride);
            vec2 kernel = max(vec2(1.5) - delta, vec2(0.0));
            float weight = kernel.x * kernel.y;
            bed += texelFetch(colortex7, pixel, 0).rgb * weight;
            sum += weight;
        }
    }
    if (sum <= 0.0001) return false;
    bed /= sum;
    return true;
}
