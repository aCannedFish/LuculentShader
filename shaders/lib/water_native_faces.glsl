#include "/lib/water_face_cache.glsl"

bool waterFacesReady() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    return imageLoad(colorimg5, ivec2(17, imageSize(colorimg5).y - 1)).r == uint(frameCounter) + 1u;
#else
    return false;
#endif
}

struct WaterFaceSample {
    vec3 albedo;
    vec2 lm;
    float ao;
    uint priority;
};

// Resolve the four real vertex attributes at the physical hit, preserving the
// sprite rotation and the owning face on either side of a material boundary.
bool waterReadLayer(int face, int layer, vec2 f, vec3 hitView, out WaterFaceSample sampleData) {
    uint priority = 0u;
    vec2 uv = vec2(0.0);
    vec2 low = vec2(1.0), high = vec2(0.0);
    vec3 tint = vec3(0.0);
    vec2 lm = vec2(0.0);
    float ao = 0.0;
    for (int i = 0; i < 4; ++i) {
        vec2 address = unpackUnorm2x16(imageLoad(colorimg5, waterFaceAddress(face, 4 + 8 * layer + i)).r);
        uint data = imageLoad(colorimg5, waterFaceAddress(face, 8 + 8 * layer + i)).r;
        priority = max(priority, data >> 28u);
        float weight = ((i & 1) == 0 ? 1.0 - f.x : f.x) * (i < 2 ? 1.0 - f.y : f.y);
        uv += weight * address;
        low = min(low, address);
        high = max(high, address);
        tint += weight * vec3(data & 31u, (data >> 5u) & 63u, (data >> 11u) & 31u) / vec3(31,63,31);
        ao += weight * float((data >> 16u) & 15u) / 15.0;
        lm += weight * vec2((data >> 20u) & 15u, (data >> 24u) & 15u);
    }
    vec2 atlas = vec2(textureSize(colortex5, 0));
    // Stay inside this sprite even when the intersection lies exactly on a corner.
    vec2 inset = min(0.5 / atlas, (high - low) * 0.5);
    float rate = max((high.x - low.x) * atlas.x, (high.y - low.y) * atlas.y);
    float footprint = 2.0 * abs(hitView.z * gbufferProjectionInverse[1][1]) / viewHeight;
    vec4 texel = textureLod(colortex5, clamp(uv, low + inset, high - inset),
        max(log2(max(rate * footprint, 1.0)), 0.0));
    if (priority != 0u && texel.a < 0.1) return false;
    sampleData = WaterFaceSample(toLinearSpace(texel.rgb * tint), (lm + 0.5) / 16.0, ao, priority);
    return true;
}

// Illuminate the selected material only when the camera cannot supply its
// radiance. Visibility traversal and overlay selection do not require GI.
vec3 waterLightFace(WaterFaceSample material, vec3 normal, vec3 hitView) {
    vec3 coord = waterShadowCoordinate(viewToWorld(hitView) + normal * 0.015);
    vec3 transfer = vec3(1.0);
    if (all(greaterThan(coord, vec3(0.0))) && all(lessThan(coord, vec3(1.0)))) {
        vec2 tap = shadowTexelCenter(coord.xy);
        float solid = textureLod(shadowtex1, tap, 0.0).r;
        float front = textureLod(shadowtex0, tap, 0.0).r;
        if (shadowDepthToBlocks(coord.z - solid) > 0.06) transfer = vec3(0.0);
        else if (shadowDepthToBlocks(coord.z - front) > 0.04) {
            vec4 cover = textureLod(shadowcolor0, tap, 0.0);
            transfer = abs(cover.a - 0.5) < 0.1 ? cover.rgb : vec3(0.0);
        }
    }
    samplingWaterCaster = true;
    vec3 radiance = computeSurfaceLighting(material.albedo, mat3(gbufferModelView) * normal,
        material.lm, transfer, material.ao, hitView);
    samplingWaterCaster = false;
    return radiance;
}

// A slot is coverage, not occupancy. Respect alpha and decline ambiguous
// overlapping materials rather than painting an unobserved face on a block.
bool waterReadFace(int face, vec2 f, vec3 hitView, out WaterFaceSample material) {
    uint a = imageLoad(colorimg5, waterFaceAddress(face, 2)).r;
    uint b = imageLoad(colorimg5, waterFaceAddress(face, 3)).r;
    if (a != 15u || (b != 0u && b != 15u)) return false;
    bool first = waterReadLayer(face, 0, f, hitView, material);
    if (b == 0u) return first;
    WaterFaceSample overlay;
    bool second = waterReadLayer(face, 1, f, hitView, overlay);
    if (!second) return first;
    if (first && overlay.priority == material.priority) return false;
    if (!first || overlay.priority > material.priority) material = overlay;
    return true;
}

// Lookup at a known face uses the physical owner, never the block beneath a
// neighbouring camera/shadow texel. This also handles coplanar sand/dirt joins.
vec4 waterOwnedColour(vec3 hitView, vec3 surfaceNormal) {
    if (!waterFacesReady()) return vec4(0.0);
    vec3 n = abs(surfaceNormal);
    int axis = n.x > max(n.y, n.z) ? 0 : (n.y > n.z ? 1 : 2);
    if (n[axis] < 0.9999) return vec4(0.0);
    vec3 normal = vec3(0.0);
    normal[axis] = sign(surfaceNormal[axis]);
    vec3 world = viewToAbsoluteWorld(hitView);
    ivec3 owner = ivec3(floor(world - normal * 0.025));
    float plane = float(owner[axis]) + (normal[axis] > 0.0 ? 1.0 : 0.0);
    if (abs(world[axis] - plane) > 0.012) return vec4(0.0);
    int face = waterFindFace(owner, axis, normal[axis] < 0.0, false);
    if (face < 0) return vec4(0.0);
    WaterFaceSample material;
    vec2 f = clamp(waterFaceAxes(world-vec3(owner), axis), 0.0, 1.0);
    if (!waterReadFace(face, f, hitView, material)) return vec4(0.0);
    return vec4(waterLightFace(material, normal, hitView), 1.0);
}

// Consult only certified faces actually submitted this frame. Cell traversal
// locates their boundary planes; it never interprets occupancy as a surface.
bool waterNearFaceHit(vec3 position, vec3 direction, float limit, out float distance,
                      out vec3 normal, out WaterFaceSample material) {
    distance = -1.0;
    if (!waterFacesReady() || limit <= 0.0) return false;
    vec3 origin = viewToAbsoluteWorld(position);
    vec3 ray = mat3(gbufferModelViewInverse) * direction;
    ivec3 grid = waterFarOrigin();
    ivec3 stepDir = ivec3(sign(ray));
    vec3 reciprocal = sign(ray) / max(abs(ray), vec3(1e-8));
    vec3 localOrigin = origin - vec3(grid);
    // Start just inside the finite capture and never clamp an off-grid cell.
    vec3 t0 = -localOrigin * reciprocal;
    vec3 t1 = (vec3(waterFarSize) - localOrigin) * reciprocal;
    vec3 entry = mix(min(t0,t1), vec3(-1e8), lessThan(abs(ray),vec3(1e-8)));
    float cursor = max(0.0, max(entry.x, max(entry.y, entry.z)));
    ivec3 cell = ivec3(floor(localOrigin + ray * (cursor + 0.0003)));
    // Carry the crossed integer boundary exactly, including nearly tangent
    // rays where a small floating-point nudge rounds back into the old cell.
    for (int visit = 0; visit < 160 && cursor < limit; ++visit) {
        if (!waterFarInside(cell)) break;
        ivec3 span = ivec3(1);
        // Ascending rays above a whole column cannot encounter one of its
        // submitted faces. Advance to the next horizontal column in one step.
        float y = localOrigin.y + cursor * ray.y;
        if (ray.y > 0.0 && y > float(imageLoad(colorimg5, waterColumnAddress(waterColumnIndex(cell,16))).r) + 0.001) {
            span = ivec3(16, 128, 16);
        } else if (ray.y > 0.0 && y > float(imageLoad(colorimg5, waterColumnAddress(waterColumnIndex(cell,4))).r) + 0.001) {
            span = ivec3(4, 128, 4);
        } else {
            uint mask = imageLoad(colorimg5, waterMacroAddress(waterMacroIndex(cell))).r;
            if (mask == 0u) span = ivec3(4);
            else if ((mask & (1u << uint(cell.y & 3))) == 0u) span = ivec3(4,1,4);
        }
        vec3 border = (vec3(cell / span) + step(vec3(0.0), ray)) * vec3(span);
        vec3 times = mix((border - localOrigin) * reciprocal, vec3(1e8), lessThan(abs(ray),vec3(1e-8)));
        int axis = times.x < min(times.y, times.z) ? 0 : (times.y < times.z ? 1 : 2);
        float t = times[axis];
        if (t > limit) break;
        cursor = max(t, cursor);
        cell = ivec3(floor(localOrigin + ray * (cursor + 0.00005)));
        cell[axis] = int(border[axis]) - int(stepDir[axis] < 0);
        if (!waterFarInside(cell)) break;
        if ((imageLoad(colorimg5, waterMacroAddress(waterMacroIndex(cell))).r & (1u << uint(cell.y & 3))) == 0u) continue;
        ivec3 owner = cell + grid;
        int face = waterFindFace(owner, axis, stepDir[axis] > 0, false);
        if (face < 0) continue;
        if (t <= 0.0005) continue;
        normal = vec3(0.0);
        normal[axis] = -float(stepDir[axis]);
        vec2 f = clamp(waterFaceAxes(origin + ray*t - vec3(owner), axis), 0.0, 1.0);
        if (waterReadFace(face, f, position + direction*t, material)) {
            distance = t;
            return true;
        }
    }
    return false;
}
