// Reconstruct the same UV frame as the submitted quad, including rotated
// and mirrored sprites. The incident air ray supplies the viewing direction
// even when the glass lies beyond the camera's colour buffer.
vec4 waterGlassRadiance(WaterFaceHit hit, vec3 normalWorld, vec3 hitView, vec3 view) {
    vec2 corners[4];
    vec2 uv = vec2(0.0);
    vec2 low = vec2(1.0);
    vec2 high = vec2(0.0);
    vec3 tint = vec3(0.0);
    vec2 lm = vec2(0.0);
    float vertexAlpha = 0.0;
    for (int i = 0; i < 4; ++i) {
        corners[i] = unpackUnorm2x16(imageLoad(colorimg5, waterFaceAddress(hit.record, 4 + i)).r);
        uint data = imageLoad(colorimg5, waterFaceAddress(hit.record, 8 + i)).r;
        float w = waterCornerWeight(i, hit.localUv);
        uv += w * corners[i];
        low = min(low, corners[i]);
        high = max(high, corners[i]);
        tint += w * vec3(data & 31u, (data >> 5u) & 63u, (data >> 11u) & 31u) / vec3(31,63,31);
        uint alpha = ((data >> 16u) & 15u) | ((data >> 24u) & 240u);
        vertexAlpha += w * float(alpha) / 255.0;
        lm += w * vec2((data >> 20u) & 15u, (data >> 24u) & 15u);
    }
    lm = (lm + 0.5) / 16.0;
    vec2 du = mix(corners[1] - corners[0], corners[3] - corners[2], hit.localUv.y);
    vec2 dv = mix(corners[2] - corners[0], corners[3] - corners[1], hit.localUv.x);
    float det = du.x * dv.y - du.y * dv.x;
    vec3 along = abs(normalWorld.x) > 0.5 ? vec3(0,0,1) : vec3(1,0,0);
    vec3 across = abs(normalWorld.y) > 0.5 ? vec3(0,0,1) : vec3(0,1,0);
    vec3 tangent = mat3(gbufferModelView) * (along * dv.y - across * du.y);
    vec3 bitangent = mat3(gbufferModelView) * (across * du.x - along * dv.x);
    vec3 geometric = mat3(gbufferModelView) * normalWorld;
    tangent = safeNormalize(tangent * sign(det), mat3(gbufferModelView) * along);
    bitangent = safeNormalize(bitangent * sign(det), cross(geometric, tangent));
    float footprint = 2.0 * abs(hitView.z * gbufferProjectionInverse[1][1]) / max(viewHeight, 1.0);
    vec2 gx = du * footprint;
    vec2 gy = dv * footprint;
    vec2 inset = min(0.5 / vec2(textureSize(colortex5, 0)), (high - low) * 0.5);
    uv = clamp(uv, low + inset, high - inset);
    if (length(hitView) <= POM_DISTANCE && abs(det) > 1e-12) {
        vec3 viewTangent = vec3(dot(view,tangent), dot(view,bitangent), dot(view,geometric));
        uv = pbrHeightUv(colortex1, uv, viewTangent, vec4((low + high) * 0.5, (high - low) * 0.5), gx, gy);
    }
    vec4 texel = textureGrad(colortex5, uv, gx, gy);
    vec4 normalMap = textureGrad(colortex1, uv, gx, gy);
    if (dot(abs(normalMap), vec4(1.0)) < 0.00001) normalMap = vec4(0.5,0.5,1.0,1.0);
    LabPbrMaterial pbr = decodeLabPbr(toLinearSpace(texel.rgb * tint), textureGrad(colortex2, uv, gx, gy), normalMap);
    vec3 normal = safeNormalize(mat3(tangent,bitangent,geometric) * pbr.tangentNormal, geometric);
    float shadow = 1.0;
    if (smoothstep(0.60, 0.96, waterSkyLevel(lm.y)) > 0.001) {
        vec4 clip = shadowProjection * shadowModelView * vec4(viewToWorld(hitView), 1.0);
        shadow = waterOpaqueShadow(clip, normal, length(hitView));
        shadow *= cloudProjectedShadow(viewToAbsoluteWorld(hitView), normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
    }
    samplingWaterCaster = true;
    vec4 layer = transparentPbrLayer(pbr, normal, tangent, hitView, view, lm, shadow, texel.a * vertexAlpha);
    samplingWaterCaster = false;
    return vec4(layer.rgb * layer.a, layer.a);
}

// A raster texel at the outline can extend beyond the glass block. When
// its submitted face is known, let its exact rectangle provide the layer.
bool waterGlassOwnsRaster(vec2 uv) {
    ivec2 pixel = ivec2(uv * vec2(viewWidth, viewHeight));
    vec4 layer = texelFetch(colortex7, pixel, 0);
    if (layer.x < 2.0) return false;
    int axis = int(layer.x) - 2;
    float plane = floor(cameraPosition[axis]) + layer.y;
    if (abs(plane - round(plane)) > 0.0002) return false;
    vec3 sampleWorld = viewToAbsoluteWorld(waterSurfacePosition(uv, layer.b));
    bool negative = cameraPosition[axis] < plane;
    ivec3 owner = ivec3(floor(sampleWorld));
    owner[axis] = int(round(plane)) - int(!negative);
    int face = waterFindFace(owner, axis, negative, false, true);
    return face >= 0 && imageLoad(colorimg5, waterFaceAddress(face, 2)).r == waterGlassMask
        && imageLoad(colorimg5, waterFaceAddress(face, 3)).r == 0u;
}

flat in vec3 vGlassLower;
flat in vec3 vGlassUpper;

// Reject rays outside the finite bounds of this frame's glass before
// starting another traversal. Parallel rays must lie in their axis slab.
float waterGlassRange(vec3 position, vec3 direction, float limit) {
    if (vGlassUpper.x < 0.0) return -1.0;
    vec3 lo = vGlassLower;
    vec3 hi = vGlassUpper;
    vec3 origin = viewToAbsoluteWorld(position) - vec3(waterFarOrigin());
    vec3 ray = mat3(gbufferModelViewInverse) * direction;
    bvec3 parallel = lessThan(abs(ray), vec3(1e-8));
    if (any(bvec3(parallel.x && (origin.x < lo.x || origin.x > hi.x),
                  parallel.y && (origin.y < lo.y || origin.y > hi.y),
                  parallel.z && (origin.z < lo.z || origin.z > hi.z)))) return -1.0;
    vec3 inv = sign(ray) / max(abs(ray), vec3(1e-8));
    vec3 a = (lo - origin) * inv;
    vec3 b = (hi - origin) * inv;
    vec3 enter = mix(min(a,b), vec3(-1e8), parallel);
    vec3 leave = mix(max(a,b), vec3(1e8), parallel);
    float last = min(limit, min(leave.x, min(leave.y, leave.z)) + 0.001);
    return last >= max(0.0, max(enter.x, max(enter.y, enter.z))) ? last : -1.0;
}

// Composite all certified transparent fronts along the ray, stopping at the
// selected opaque receiver. Keep a camera-only pane at its measured distance.
vec4 waterExitLayers(vec3 position, vec3 ray, float limit, WaterRayHit layer) {
    WaterLayers layers = WaterLayers(vec4(0.0), vec4(0.0), -1.0);
    float range = waterGlassRange(position, ray, min(limit, 96.0));
    bool recorded = range > 0.0;
    if (layer.distance > 0.0 && layer.distance < limit && !(vGlassUpper.x >= 0.0 && waterGlassOwnsRaster(layer.uv))) {
        layers.screenDistance = layer.distance;
        layers.screenColour = waterScreenLayer(layer.uv);
    }
    if (recorded) {
        float unusedDistance;
        vec3 unusedNormal;
        WaterFaceHit unusedMaterial;
        waterTraceFaces(position, ray, range, unusedDistance, unusedNormal, unusedMaterial, true, layers);
    }
    if (layers.screenDistance > 0.0) appendWaterLayer(layers.colour, layers.screenColour);
    return layers.colour;
}
