// A screen or shadow texel at a silhouette can extend past the last real
// corner. Reject that extension only when the full rectangle is recorded.
bool waterExitFaceContains(vec3 sampleWorld, vec3 hitWorld, vec3 normal) {
    vec3 n = abs(normal);
    int axis = n.x > max(n.y, n.z) ? 0 : (n.y > n.z ? 1 : 2);
    if (n[axis] < 0.9999) return true;
    if (waterSharesFaceBlock(sampleWorld, hitWorld, normal)) return true;
    ivec3 owner = ivec3(floor(sampleWorld - 0.01 * normal));
    bool negative = normal[axis] < 0.0;
    float plane = float(owner[axis] + int(!negative));
    return abs(sampleWorld[axis] - plane) > 0.012 || !waterFacesReady()
        || !waterOpaqueUnitFace(owner, axis, negative);
}

// Trace light leaving the water from the actual interface. The native face
// records can see beyond the camera, while depthtex2 and colortex15 pair
// on-screen scene geometry with its colour before the viewmodel was drawn.
vec3 waterExitRadiance(vec2 uv, vec3 interfaceView, vec3 airDirection,
                       out vec2 sourceUv, out bool cameraSource) {
    // With refraction disabled, the ordinary camera already observes this
    // direction. Keep the pre-hand source and skip the off-screen ray search.
    if (WATER_REFRACTION_STRENGTH <= 0.0) {
        sourceUv = uv;
        cameraSource = true;
        vec4 source = texelFetch(colortex15,ivec2(uv * vec2(viewWidth,viewHeight)),0);
        vec3 radiance = source.a > 0.0 ? source.rgb : underwaterBackgroundColor(uv);
        return applyTransparentLayer(radiance,waterScreenLayer(uv));
    }
    vec3 ray = mat3(gbufferModelView) * airDirection;
    vec3 faceNormal;
    WaterFaceHit material;
    WaterRayHit layer;
    WaterRayHit seen = traceWaterGeometry(uv, interfaceView, ray, far, depthtex2, true, layer);
    vec2 pixelUv = waterBedUv(seen.uv);
    ivec2 pixel = ivec2(pixelUv * vec2(viewWidth, viewHeight));
    bool fromCamera = seen.distance > 0.0 && texelFetch(colortex15, pixel, 0).a > 0.0;
    if (fromCamera) {
        float depth = texelFetch(depthtex2, pixel, 0).r;
        float face = fract(texelFetch(colortex6, pixel, 0).a);
        if (depth == texelFetch(depthtex1, pixel, 0).r && face >= 0.0625 && face < 0.4375) {
            fromCamera = waterExitFaceContains(viewToAbsoluteWorld(screenToView(pixelUv, depth)),
                viewToAbsoluteWorld(interfaceView + ray * seen.distance), waterAxisNormal(face));
        }
    }
    float distance = fromCamera ? seen.distance : -1.0;
    bool useFace = false;
    vec2 sunPixel;
    bool supported = fromCamera && waterCameraHitSupported(seen, interfaceView, ray, depthtex2, true);
    if (seen.hidden || (seen.distance > 0.0 && !supported)) {
        // Stop at a supported camera surface. Otherwise search beyond the
        // silhouette for off-screen faces, cutouts and shadow-view geometry.
        float extent = supported ? distance : min(far, 96.0);
        float faceDistance;
        useFace = waterNearFaceHit(interfaceView, ray, extent, faceDistance, faceNormal, material);
        if (useFace) {
            distance = faceDistance;
            extent = faceDistance - 0.015;
            fromCamera = false;
        }
        float sunDistance;
        if (extent > 0.008 && waterSunIntersection(interfaceView, ray, extent, sunDistance, sunPixel)
            && waterExitFaceContains(waterShadowPoint(sunPixel, textureLod(shadowtex1, sunPixel, 0.0).r) + cameraPosition,
                viewToAbsoluteWorld(interfaceView + ray * sunDistance), waterCasterNormal(sunPixel))) {
            distance = sunDistance;
            fromCamera = false;
            useFace = false;
        }
    }
    vec3 radiance;
    if (distance > 0.0) {
        vec3 hit = interfaceView + ray * distance;
        sourceUv = seen.uv;
        cameraSource = fromCamera;
        if (!cameraSource) cameraSource = waterCameraSees(hit, depthtex2, sourceUv);
        if (cameraSource) {
            radiance = reflectionSourceRadiance(colortex15, depthtex2, sourceUv);
        } else if (useFace) {
            radiance = waterLightFace(material, faceNormal, hit);
        } else {
            radiance = waterCasterRadiance(sunPixel, hit).rgb;
        }
    } else {
        vec4 clip = gbufferProjection * vec4(interfaceView + ray * far, 1.0);
        sourceUv = clip.xy / max(clip.w, 0.001) * 0.5 + 0.5;
        cameraSource = clip.w > 0.0 && all(greaterThan(sourceUv, vec2(0.0)))
            && all(lessThan(sourceUv, vec2(1.0)));
        vec4 cloud = cloudEnvironment(airDirection);
        radiance = cloud.rgb + skyRadiance(airDirection) * (1.0 - cloud.a);
    }
    {
        vec4 colour = waterExitLayers(interfaceView, ray, distance > 0.0 ? distance : far, layer);
        radiance = applyTransparentLayer(radiance, colour);
    }
    return radiance;
}
