/* Distant optics share one reflected and one refracted ray per screen tile.
 * C7 contains the shaded bed. Above water C15 is free after the opaque pass;
 * its signed water depth distinguishes a geometry hit from open sky.
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

// Both resolutions must sample the same angular field. Retain the resolved
// short ripple near the eye; the coarser footprint gradually loses that tilt.
vec3 waterMirrorNormal(vec3 position, vec3 opticalNormal, vec3 detailNormal, float lod) {
#if ENABLE_WATER_WAVES == 1
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 ripple = detailNormal - opticalNormal;
    float limit = 0.012 * WATER_WAVE_STRENGTH * (1.0 - lod)
        * smoothstep(0.0, 0.16, dot(up, -normalize(position)));
    return normalize(opticalNormal + ripple * (limit / (0.10 + length(ripple))));
#else
    return opticalNormal;
#endif
}

// Far mirrors need the broad silhouette rather than a subpixel face ID. Look
// for the first depth crossing in eight intervals and refine the interval twice.
// Foreground geometry before the interface and submerged texels cannot supply air radiance.
bool distantWaterCrossing(vec3 position, vec3 ray, vec3 up, float t, out ivec2 pixel) {
    vec3 probe = position + ray * t;
    if (probe.z >= -near) return false;
    vec2 projected = waterProjectPixel(probe, vec2(textureSize(depthtex1, 0)));
    if (any(lessThan(projected, vec2(0))) || any(greaterThanEqual(projected, vec2(textureSize(depthtex1, 0))))) return false;
    pixel = ivec2(projected);
    float depth = texelFetch(depthtex1, pixel, 0).r;
    if (depth >= 0.999999) return false;
    vec2 uv = (vec2(pixel) + 0.5) / vec2(textureSize(depthtex1, 0));
    vec3 receiver = screenToView(uv, depth);
    if (receiver.z < probe.z || dot(receiver - position, ray) <= 0.01) return false;
    return dot(receiver - position, up) >= -0.03 && texelFetch(colortex6, pixel, 0).a < 4.5;
}

vec4 distantWaterRadiance(vec3 position, vec3 ray, float skyLevel) {
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    float previous = 0.0;
    for (int i = 1; i <= 8; ++i) {
        float u = float(i) / 8.0;
        float t = far * u * u;
        ivec2 hit;
        if (distantWaterCrossing(position, ray, up, t, hit)) {
            for (int j = 0; j < 2; ++j) {
                float mid = 0.5 * (previous + t);
                ivec2 candidate;
                if (distantWaterCrossing(position, ray, up, mid, candidate)) {
                    hit = candidate;
                    t = mid;
                } else previous = mid;
            }
            vec2 source = (vec2(hit) + 0.5) / vec2(textureSize(colortex6, 0));
            return vec4(waterBankLayer(source, texelFetch(colortex6, hit, 0).rgb, position), 1.0);
        }
        previous = t;
    }
    // At a disocclusion a missed screen ray can still meet the back bank.
    // Resolve these misses once per tile using actual submitted geometry.
    float distance;
    vec3 face;
    WaterFaceHit material;
    if (waterNearFaceHit(position, ray, far, distance, face, material)) {
        vec3 point = position + ray * distance;
        vec2 source;
        if (waterCameraSees(point, source)) {
            ivec2 pixel = ivec2(source * vec2(textureSize(colortex6, 0)));
            return vec4(waterBankLayer(source, texelFetch(colortex6, pixel, 0).rgb, position), 1.0);
        }
        return vec4(waterLightFace(material, face, point), 1.0);
    }
    vec3 direction = mat3(gbufferModelViewInverse) * ray;
#if SIMPLE_DIMENSION == 0
    vec4 cloud = cloudEnvironment(direction);
    vec3 sky = skyAtmosphereRadiance(direction) + skyStars(direction);
    return vec4((cloud.rgb + sky * (1.0 - cloud.a)) * reflectionSkyLightWeight(skyLevel), -1.0);
#else
    return vec4(waterEnvironment(viewToAbsoluteWorld(position), direction, reflectionSkyLightWeight(skyLevel), false), -1.0);
#endif
}

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

bool readDistantWater(vec3 centre, bool includeBed, out vec3 bed, out vec3 reflection, out vec4 solid) {
    ivec2 last = textureSize(colortex15, 0) - 1;
    ivec2 tile = ivec2(gl_FragCoord.xy) / distantWaterStride;
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec3 terrain = vec3(0.0);
    vec3 sky = vec3(0.0);
    float terrainWeight = 0.0;
    float skyWeight = 0.0;
    bed = vec3(0.0);
    reflection = vec3(0.0);
    solid = vec4(0.0);
    // A compact tent filter softens fine silhouettes. Separate sky and solid
    // contributions so one unsupported sky sample cannot punch a blue dot in a wall.
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            ivec2 cell = tile + ivec2(x, y);
            if (any(lessThan(cell, ivec2(0))) || any(greaterThan(cell, last / distantWaterStride))) continue;
            ivec2 pixel = distantWaterAnchor(cell, last);
            vec4 tap = texelFetch(colortex15, pixel, 0);
            if (tap.a == 0.0) continue;
            vec2 uv = (vec2(pixel) + 0.5) / vec2(last + 1);
            vec3 position = waterSurfacePosition(uv, abs(tap.a));
            if (abs(dot(position - centre, up)) > 0.16 + abs(tap.a) * 0.0005) continue;
            vec2 delta = abs(vec2(pixel) + 0.5 - gl_FragCoord.xy) / float(distantWaterStride);
            vec2 kernel = max(vec2(1.5) - delta, vec2(0.0));
            float weight = kernel.x * kernel.y;
            if (includeBed) bed += texelFetch(colortex7, pixel, 0).rgb * weight;
            if (tap.a > 0.0) {
                terrain += tap.rgb * weight;
                terrainWeight += weight;
            } else {
                sky += tap.rgb * weight;
                skyWeight += weight;
            }
        }
    }
    float total = terrainWeight + skyWeight;
    if (total < 0.0001) return false;
    bed /= total;
    float skyFraction = skyWeight / total;
    skyFraction *= smoothstep(0.12, 0.50, skyFraction);
    solid = vec4(terrain / max(terrainWeight, 0.0001), terrainWeight / total);
    reflection = mix(solid.rgb, sky / max(skyWeight, 0.0001), skyFraction);
    return true;
}
