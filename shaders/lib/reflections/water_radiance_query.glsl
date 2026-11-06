// Reflection-only receiver queries. Other optical programs do not parse
// or link this screen/environment search when they resolve transmission.
#ifndef LUCULENT_WATER_RADIANCE_QUERY
#define LUCULENT_WATER_RADIANCE_QUERY

#include "/lib/water_reflection_trace.glsl"

// A current opaque observation can bound its own coherent plane. Cutouts,
// mixed-depth observations and occluded history cannot establish that bound.
bool waterEnvironmentReceiverIsCoherent(WaterEnvironmentSupport support) {
    vec3 relative = support.point - (cameraPosition - previousCameraPosition);
    vec3 source = (gbufferModelView * vec4(relative, 1.0)).xyz;
    vec2 uv;
    if (!waterCameraSees(source, uv)) return false;
    ivec2 pixel = ivec2(uv * vec2(textureSize(depthtex1, 0)));
    float tag = texelFetch(colortex6, pixel, 0).a;
    if (tag < 0.5 || tag > 2.5 || fract(tag) == 0.5) return false;
    vec3 normal = waterBedNormal(uv, source, depthtex1);
    vec3 axis = abs(normal);
    int major = axis.x > max(axis.y, axis.z) ? 0 : (axis.y > axis.z ? 1 : 2);
    if (axis[major] < 0.9999) return false;
    // Two normalized-depth ULPs converted to world distance at this receiver.
    float tolerance = max(0.01, source.z * source.z * 1.2e-7 / max(near, 0.01));
    float footprint = max(length(support.point) * 6.0 / float(waterEnvironmentSide), 0.02);
    return support.variance[major] <= tolerance * tolerance
        && support.rangeDeviation <= footprint * 2.0;
}

// The coarse range only guides the search. Full-resolution intersections must
// still own their source pixel. Empty depth may reject only a bounded receiver,
// never an arbitrary mixed or alpha-tested environment observation.
vec4 waterRefineEnvironmentReceiver(vec3 origin, vec3 ray, float estimate,
                                    WaterEnvironmentSupport support, out bool outsideReceiver) {
    outsideReceiver = false;
    bool boundedReceiver = waterEnvironmentReceiverIsCoherent(support);
    ivec2 size = textureSize(depthtex1, 0);
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    float distance = estimate;
    for (int iteration = 0; iteration < 3; ++iteration) {
        vec3 point = origin + ray * distance;
        if (point.z >= -near) return vec4(0.0);
        vec4 clip = gbufferProjection * vec4(point, 1.0);
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        ivec2 pixel = ivec2(floor(uv * vec2(size)));
        if (any(lessThan(pixel, ivec2(1))) || any(greaterThanEqual(pixel, size - 1))) return vec4(0.0);
        float depth = texelFetch(depthtex1, pixel, 0).r;
        if (depth >= 0.999999) {
            outsideReceiver = boundedReceiver
                && texelFetch(depthtex1, pixel + ivec2(1, 0), 0).r >= 0.999999
                && texelFetch(depthtex1, pixel - ivec2(1, 0), 0).r >= 0.999999
                && texelFetch(depthtex1, pixel + ivec2(0, 1), 0).r >= 0.999999
                && texelFetch(depthtex1, pixel - ivec2(0, 1), 0).r >= 0.999999;
            return vec4(0.0);
        }
        uv = (vec2(pixel) + 0.5) / vec2(size);
        vec3 receiver = screenToView(uv, depth);
        if (dot(receiver - origin, up) < -0.03) return vec4(0.0);
        float tag = texelFetch(colortex6, pixel, 0).a;
        if (tag >= 4.5) return vec4(0.0);
        if (tag > 2.5) {
            distance = dot(receiver - origin, ray);
        } else {
            vec3 normal = mat3(gbufferModelView) * waterBedNormal(uv, receiver, depthtex1);
            float cosine = dot(normal, ray);
            if (cosine >= -0.001) return vec4(0.0);
            distance = dot(receiver - origin, normal) / cosine;
        }
        if (distance <= 0.02 || distance > far) return vec4(0.0);
        vec3 hit = origin + ray * distance;
        vec2 witness;
        if (waterCameraSees(hit, witness)) {
            vec3 radiance = filteredWaterReflection(witness, distance, -hit.z, WATER_ROUGHNESS).rgb;
            return vec4(waterBankLayer(witness, radiance, origin), distance);
        }
    }
    return vec4(0.0);
}

// Query unweighted reflected radiance before the water BRDF and air medium.
// Confidence guides temporal reuse; it never acts as a sky blend opacity.
vec4 queryWaterRadiance(vec3 position, vec3 direction, float roughness, float skyLevel) {
    vec3 originWorld = viewToAbsoluteWorld(position);
    vec2 uv = waterProjectPixel(position, vec2(1.0));
    vec3 up = mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0);
    vec4 aboveWater = vec4(up, 0.01 - dot(up, position));
    ScreenReflectionHit screenHit = traceWaterImageDetailed(
        colortex6, depthtex1, position, direction, 0.02, far,
        min(96, WATER_REFLECTION_STEPS + 16), aboveWater);
    WaterRayHit hit = WaterRayHit(screenHit.uv,
        screenHit.coverage > 0.0 ? screenHit.distance : -1.0,
        !screenHit.refined || screenHit.confidence < 0.75);
    bool visible = hit.distance > 0.0 && !waterReflectionSubmerged(hit.uv, position);
    float maximum = visible ? max(hit.distance - 0.05, 0.0) : far;
    if (!visible || hit.hidden) {
        float sunDistance = -1.0;
        vec2 sunPixel;
        bool sunHit = REFLECTION_OCCLUSION_STEPS > 0
            && waterSunIntersection(position, direction, maximum, sunDistance, sunPixel);
        float faceDistance;
        vec3 faceNormal;
        WaterFaceHit material;
        bool nativeHit = waterNearFaceHit(position, direction,
            min(sunHit ? sunDistance + 0.015 : maximum, far), faceDistance, faceNormal, material);
        if (nativeHit || sunHit) {
            float distance = nativeHit ? faceDistance : sunDistance;
            vec3 point = position + direction * distance;
            vec2 witness;
            vec3 radiance;
            if (waterCameraSees(point, witness)) {
                radiance = filteredWaterReflection(witness, distance,
                    reflectionSceneDepth(depthtex1, witness), roughness).rgb;
                radiance = waterBankLayer(witness, radiance, position);
            } else if (nativeHit) {
                radiance = waterLightFace(material, faceNormal, point);
            } else {
                radiance = waterCasterRadiance(sunPixel, point).rgb;
            }
            return vec4(reflectionAirMedium(radiance, distance, direction, position), distance);
        }
    }
    if (visible) {
        vec4 sampleColor = filteredWaterReflection(hit.uv, hit.distance,
            reflectionSceneDepth(depthtex1, hit.uv), roughness);
        sampleColor.rgb = waterBankLayer(hit.uv, sampleColor.rgb, position);
        // At an uncertain or viewport-edge screen hit, transition to a local
        // scene observation when it describes the same range of receivers.
        // A known wall is never blended with the sky merely for touching an edge.
        if (screenHit.confidence < 0.999) {
            vec4 localScene = sampleWaterEnvironment(position, direction, up);
            float tolerance = max(0.5, hit.distance * 0.20);
            if (localScene.a > 0.0 && abs(localScene.a - hit.distance) < tolerance) {
                sampleColor.rgb = mix(localScene.rgb, sampleColor.rgb,
                    smoothstep(0.0, 0.95, screenHit.confidence));
            }
        }
        if (sampleColor.a > 0.0) return vec4(reflectionAirMedium(sampleColor.rgb, hit.distance, direction, position), hit.distance);
    }
    WaterEnvironmentSupport support;
    vec4 capturedEnvironment = sampleWaterEnvironment(position, direction, up, support);
    if (capturedEnvironment.a > 0.0) {
        bool outsideReceiver;
        vec4 receiverSample = waterRefineEnvironmentReceiver(position, direction,
            capturedEnvironment.a, support, outsideReceiver);
        if (receiverSample.a > 0.0) capturedEnvironment = receiverSample;
        else if (outsideReceiver) capturedEnvironment.a = 0.0;
    }
    if (capturedEnvironment.a > 0.0) {
        capturedEnvironment.rgb = reflectionAirMedium(capturedEnvironment.rgb,
            capturedEnvironment.a, direction, position);
        return capturedEnvironment;
    }
    vec3 rayWorld = mat3(gbufferModelViewInverse) * direction;
    vec3 sky = waterEnvironment(originWorld, rayWorld, reflectionSkyLightWeight(skyLevel), false);
    return vec4(reflectionAirMedium(sky, far, direction, position),
        screenHit.confidence > 0.9 ? -1.0 : -2.0);
}

#endif
