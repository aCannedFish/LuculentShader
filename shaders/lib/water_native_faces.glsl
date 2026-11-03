#include "/lib/water_face_cache.glsl"

bool waterFacesReady() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    return imageLoad(colorimg5, ivec2(17, imageSize(colorimg5).y - 1)).r == uint(frameCounter) + 1u;
#else
    return false;
#endif
}

// A completed single solid rectangle supports clipping to its true block
// bounds. Partial primitives and translucent or ambiguous layers cannot.
bool waterOpaqueUnitFace(ivec3 owner, int axis, bool negative) {
    int face = waterFindFace(owner, axis, negative, false);
    return face >= 0 && imageLoad(colorimg5, waterFaceAddress(face, 2)).r == 15u
        && imageLoad(colorimg5, waterFaceAddress(face, 3)).r == 0u;
}

struct WaterFaceHit {
    int record;
    int layer;
    vec2 localUv;
};

float waterCornerWeight(int corner, vec2 uv) {
    return ((corner & 1) == 0 ? 1.0 - uv.x : uv.x) * (corner < 2 ? 1.0 - uv.y : uv.y);
}

// Alpha tests and final shading use the same four captured UVs and mip level.
vec4 waterFaceTexel(WaterFaceHit hit, vec3 hitView) {
    vec2 uv = vec2(0.0);
    vec2 low = vec2(1.0);
    vec2 high = vec2(0.0);
    for (int i = 0; i < 4; ++i) {
        ivec2 slot = waterFaceAddress(hit.record, 4 + 8 * hit.layer + i);
        vec2 address = unpackUnorm2x16(imageLoad(colorimg5, slot).r);
        uv += waterCornerWeight(i, hit.localUv) * address;
        low = min(low, address);
        high = max(high, address);
    }
    vec2 atlas = vec2(textureSize(colortex5, 0));
    vec2 inset = min(0.5 / atlas, (high - low) * 0.5);
    float rate = max((high.x - low.x) * atlas.x, (high.y - low.y) * atlas.y);
    float footprint = 2.0 * abs(hitView.z * gbufferProjectionInverse[1][1]) / viewHeight;
    return textureLod(colortex5, clamp(uv, low + inset, high - inset),
        max(log2(max(rate * footprint, 1.0)), 0.0));
}

// Fetch colour, AO and lightmap only for a receiver that actually needs
// native shading. A visibility query on an opaque face needs none of them.
vec3 waterLightFace(WaterFaceHit hit, vec3 normal, vec3 hitView) {
    vec3 tint = vec3(0.0);
    vec2 lm = vec2(0.0);
    float ao = 0.0;
    for (int i = 0; i < 4; ++i) {
        uint data = imageLoad(colorimg5, waterFaceAddress(hit.record, 8 + 8 * hit.layer + i)).r;
        float weight = waterCornerWeight(i, hit.localUv);
        tint += weight * vec3(data & 31u, (data >> 5u) & 63u, (data >> 11u) & 31u) / vec3(31,63,31);
        ao += weight * float((data >> 16u) & 15u) / 15.0;
        lm += weight * vec2((data >> 20u) & 15u, (data >> 24u) & 15u);
    }
    vec3 albedo = toLinearSpace(waterFaceTexel(hit, hitView).rgb * tint);
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
    vec3 radiance = computeSurfaceLighting(albedo, mat3(gbufferModelView) * normal,
        (lm + 0.5) / 16.0, transfer, ao, hitView);
    samplingWaterCaster = false;
    return radiance;
}

// A slot is coverage, not occupancy. Respect alpha and decline ambiguous
// overlapping materials rather than painting an unobserved face on a block.
bool waterReadFace(int face, vec2 f, vec3 hitView, out WaterFaceHit material) {
    uint a = imageLoad(colorimg5, waterFaceAddress(face, 2)).r;
    uint b = imageLoad(colorimg5, waterFaceAddress(face, 3)).r;
    if (((a | b) & waterGlassMask) != 0u) return false;
    if ((a & 31u) != 15u || (b != 0u && (b & 31u) != 15u)) return false;
    material = WaterFaceHit(face, 0, f);
    int firstPriority = max(findMSB(a >> 8u), 0);
    bool first = firstPriority == 0 || waterFaceTexel(material, hitView).a >= 0.1;
    if (b == 0u) return first;
    WaterFaceHit overlay = WaterFaceHit(face, 1, f);
    int secondPriority = max(findMSB(b >> 8u), 0);
    bool second = secondPriority == 0 || waterFaceTexel(overlay, hitView).a >= 0.1;
    if (!second) return first;
    if (first && secondPriority == firstPriority) return false;
    if (!first || secondPriority > firstPriority) material = overlay;
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
    WaterFaceHit material;
    vec2 f = clamp(waterFaceAxes(world-vec3(owner), axis), 0.0, 1.0);
    if (!waterReadFace(face, f, hitView, material)) return vec4(0.0);
    return vec4(waterLightFace(material, normal, hitView), 1.0);
}

// In an empty height band, advance to the next recorded band or the column
// boundary. Ascending, descending and horizontal rays use the same occupancy.
bool waterColumnGap(uint mask, int y, int stepY, out int edge) {
    int band = y >> 1;
    if ((mask & (1u << uint(band))) != 0u) return false;
    if (stepY >= 0) {
        int next = findLSB(mask & (0xffffffffu << uint(band)));
        edge = next < 0 ? waterFarSize.y : next * 2;
    } else {
        int next = findMSB(mask & (0xffffffffu >> uint(31 - band)));
        edge = (next + 1) * 2;
    }
    return true;
}

// Consult only certified faces actually submitted this frame. Cell traversal
// locates their boundary planes; it never interprets occupancy as a surface.
struct WaterLayers {
    vec4 colour;
    vec4 screenColour;
    float screenDistance;
};

void appendWaterLayer(inout vec4 foreground, vec4 background) {
    foreground += (1.0 - foreground.a) * background;
}

#ifdef WATER_NATIVE_GLASS
vec4 waterGlassRadiance(WaterFaceHit hit, vec3 normalWorld, vec3 hitView, vec3 view);
#endif

bool waterTraceFaces(vec3 position, vec3 direction, float limit, out float distance,
                     out vec3 normal, out WaterFaceHit material, bool glassOnly, inout WaterLayers layers) {
    distance = -1.0;
    if (!waterFacesReady() || limit <= 0.0) return false;
    vec3 relativeOrigin = viewToWorld(position);
    vec3 origin = relativeOrigin + cameraPosition;
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
    if (!waterFarInside(cell)) return false;
    int macro = waterMacroIndex(cell);
    uint mask = imageLoad(colorimg5, waterMacroAddress(macro)).r;
    uvec3 facing = uvec3(1u, 4u, 16u) << uvec3(greaterThan(stepDir, ivec3(0)));
    uint wanted = facing.x | facing.y | facing.z;
    int previousLarge = -1;
    int previousSmall = -1;
    uint largeColumn = 0u;
    uint smallColumn = 0u;
    // Carry the crossed integer boundary exactly, including nearly tangent
    // rays where a small floating-point nudge rounds back into the old cell.
    for (int visit = 0; visit < 160 && cursor < limit; ++visit) {
        ivec3 span = ivec3(1);
        int large = waterColumnIndex(cell, 16);
        if (large != previousLarge) {
            largeColumn = imageLoad(colorimg5, glassOnly ? waterGlassColumn(large - 1024)
                                                          : waterColumnAddress(large)).r;
            previousLarge = large;
        }
        int edgeY = 0;
        if (waterColumnGap(largeColumn, cell.y, stepDir.y, edgeY)) {
            span = ivec3(16, 128, 16);
        } else {
            int small = waterColumnIndex(cell, 4);
            if (small != previousSmall) {
                smallColumn = imageLoad(colorimg5, waterColumnAddress(small)).r;
                previousSmall = small;
            }
            uint allSlices = mask | (mask >> 6u) | (mask >> 12u) | (mask >> 18u);
            ivec3 halfCell = (cell & 3) >> 1;
            int octant = halfCell.x + 2 * halfCell.y + 4 * halfCell.z;
            if (waterColumnGap(smallColumn, cell.y, stepDir.y, edgeY)) {
                span = ivec3(4, 128, 4);
            } else if ((allSlices & wanted) == 0u) {
                span = ivec3(4);
            } else if ((mask & (1u << uint(24 + octant))) == 0u) {
                span = ivec3(2);
            } else {
                // A floor without a wall in this slice only needs the next
                // vertical crossing. Recheck on entering a different slice.
                uint slice = mask >> uint(6 * (cell.y & 3));
                span.x = (slice & facing.x) == 0u ? 4 : 1;
                span.z = (slice & facing.z) == 0u ? 4 : 1;
            }
        }
        ivec3 lower = cell & ~(span - 1);
        ivec3 upper = lower + span;
        if (span.y == 128) {
            if (stepDir.y < 0) lower.y = edgeY;
            else upper.y = edgeY;
        }
        vec3 border = mix(vec3(lower), vec3(upper), greaterThanEqual(ray, vec3(0.0)));
        vec3 times = mix((border - localOrigin) * reciprocal, vec3(1e8), lessThan(abs(ray),vec3(1e-8)));
        int axis = times.x < min(times.y, times.z) ? 0 : (times.y < times.z ? 1 : 2);
        float t = times[axis];
        if (t > limit) break;
        cursor = max(t, cursor);
        // Only the selected axis leaves this span. A distance epsilon can
        // jump a second boundary and miss the narrow top of a submerged step.
        // A span can cross several cells in a tangent direction. Evaluate
        // the final side relative to a nearby integer plane; adding the
        // grid origin first can round a micrometre-wide hit into the next cell.
        ivec3 nearPlane = ivec3(round(localOrigin + ray * cursor));
        precise vec3 relative = fma(ray, vec3(cursor), localOrigin - vec3(nearPlane));
        cell = clamp(nearPlane - ivec3(lessThan(relative, vec3(0.0))), lower, upper - 1);
        cell[axis] = int(border[axis]) - int(stepDir[axis] < 0);
        if (!waterFarInside(cell)) break;
        int nextMacro = waterMacroIndex(cell);
        if (nextMacro != macro) {
            macro = nextMacro;
            mask = imageLoad(colorimg5, waterMacroAddress(macro)).r;
        }
        if (((mask >> uint(6 * (cell.y & 3))) & facing[axis]) == 0u) continue;
        ivec3 owner = cell + grid;
        int face = waterFindFace(owner, axis, stepDir[axis] > 0, false, glassOnly);
        if (face < 0) continue;
        // Reconstruct the final distance against the actual integer plane in
        // camera-relative space. The traversal grid has up to 128 cells, so
        // rounding its origin can noticeably shift a nearly parallel hit.
        float plane = float(owner[axis] + int(stepDir[axis] < 0));
        precise float hitDistance = ((plane - cameraPosition[axis]) - relativeOrigin[axis]) * reciprocal[axis];
        if (hitDistance <= 0.0005 || hitDistance > limit) continue;
        normal = vec3(0.0);
        normal[axis] = -float(stepDir[axis]);
        vec3 localHit = fma(ray, vec3(hitDistance), relativeOrigin + (cameraPosition - vec3(owner)));
        vec2 f = clamp(waterFaceAxes(localHit, axis), 0.0, 1.0);
#ifdef WATER_NATIVE_GLASS
        if (glassOnly) {
            if (imageLoad(colorimg5, waterFaceAddress(face, 2)).r != waterGlassMask
                || imageLoad(colorimg5, waterFaceAddress(face, 3)).r != 0u) continue;
            // Prefer the recorded material at a matched plane. A separate
            // camera-only layer (a pane or an oblique model) keeps its depth order.
            if (layers.screenDistance > 0.0 && layers.screenDistance <= hitDistance + 0.008) {
                if (layers.screenDistance < hitDistance - 0.008) appendWaterLayer(layers.colour, layers.screenColour);
                layers.screenDistance = -1.0;
            }
            vec4 colour = waterGlassRadiance(WaterFaceHit(face, 0, f), normal,
                position + direction * hitDistance, -direction);
            appendWaterLayer(layers.colour, colour);
            if (layers.colour.a >= 0.9999) break;
            continue;
        }
#endif
        if (waterReadFace(face, f, position + direction * hitDistance, material)) {
            distance = hitDistance;
            return true;
        }
    }
    return false;
}

bool waterNearFaceHit(vec3 position, vec3 direction, float limit, out float distance,
                      out vec3 normal, out WaterFaceHit material) {
    WaterLayers unused;
    return waterTraceFaces(position, direction, limit, distance, normal, material, false, unused);
}
