/* Intersect a Snell ray with visible opaque surfaces. The two tile sizes
 * accelerate empty intervals. At a candidate pixel we intersect its local
 * surface plane and test the subpixel projection against that pixel's support.
 * Positions and distances remain in view space throughout the traversal.
 */
uniform sampler2D colortex14;

struct WaterRayHit {
    vec2 uv;
    float distance;
    bool hidden;
};

vec2 waterProjectPixel(vec3 position, vec2 size) {
    vec4 clip = gbufferProjection * vec4(position, 1.0);
    return (clip.xy / clip.w * 0.5 + 0.5) * size;
}

float waterTileExit(vec2 start, vec2 direction, ivec2 pixel, int side) {
    vec2 edge = (vec2(pixel / side) + step(vec2(0.0), direction)) * float(side);
    vec2 next = (edge - start) / vec2(
        abs(direction.x) > 0.000001 ? direction.x : 1.0,
        abs(direction.y) > 0.000001 ? direction.y : 1.0);
    if (abs(direction.x) <= 0.000001) next.x = 1e8;
    if (abs(direction.y) <= 0.000001) next.y = 1e8;
    return min(next.x, next.y);
}

// At a shared crease the centre sample covers only one of two faces.
// Intersect both tagged planes, clip each to the side occupied by its native
// sample, and return a colour footprint on the winning face.
WaterRayHit waterCreaseHit(ivec2 pixel, vec3 point, vec3 normal, int mask,
                          vec3 origin, vec3 ray, float limit, sampler2D depths, vec2 size) {
    const ivec2 offsets[4] = ivec2[4](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));
    float d = dot(normal, ray);
    float centreT = d < -0.0001 ? dot(normal, point - origin) / d : -1.0;
    vec3 centreHit = origin + ray * centreT;
    vec2 centrePixel = waterProjectPixel(centreHit, size);
    bool centreOK = centreT > 0.0005 && centreT <= limit
        && all(lessThanEqual(abs(centrePixel - vec2(pixel) - 0.5), vec2(0.501)));
    float nearest = limit + 1.0;
    vec2 uv = vec2(0.0);
    for (int i = 0; i < 4; ++i) {
        if ((mask & (1 << i)) == 0) continue;
        ivec2 neighbour = clamp(pixel + offsets[i], ivec2(0), ivec2(size) - 1);
        vec2 otherUv = (vec2(neighbour) + 0.5) / size;
        vec3 other = screenToView(otherUv, texelFetch(depths, neighbour, 0).r);
        vec3 side = mat3(gbufferModelView) * waterAxisNormal(texelFetch(colortex6, neighbour, 0).a);
        if (abs(dot(side, normal)) > 0.1) continue;
        float reach = abs(point.z) * abs(gbufferProjectionInverse[1][1]) * 4.0 / size.y;
        float facing = min(abs(dot(normal, normalize(point))), abs(dot(side, normalize(other))));
        if (length(other - point) > min(0.35, reach / max(facing, 0.02))) continue;
        float firstSide = dot(point - other, side);
        float secondSide = dot(other - point, normal);
        if (dot(centreHit - other, side) * sign(firstSide) < -0.0001) centreOK = false;
        float denominator = dot(side, ray);
        if (denominator >= -0.0001) continue;
        float t = dot(side, other - origin) / denominator;
        if (t <= 0.0005 || t > limit || t >= nearest) continue;
        vec3 hit = origin + ray * t;
        if (dot(hit - point, normal) * sign(secondSide) < -0.0001) continue;
        vec2 projected = waterProjectPixel(hit, size);
        if (any(greaterThan(abs(projected - vec2(pixel) - 0.5), vec2(0.501)))) continue;
        nearest = t;
        uv = clamp(projected, vec2(neighbour) + 0.001, vec2(neighbour) + 0.999) / size;
    }
    if (centreOK && centreT < nearest) return WaterRayHit(centrePixel / size, centreT, false);
    return WaterRayHit(uv, nearest <= limit ? nearest : -1.0, false);
}

WaterRayHit traceWaterGeometry(vec2 uv, vec3 origin, vec3 direction, float range, sampler2D depths) {
    vec2 size = vec2(textureSize(depths, 0));
    if (direction.z > 0.001) range = min(range, (-near * 1.02 - origin.z) / direction.z);
    vec3 end = origin + direction * max(range, 0.0);
    vec2 start = uv * size;
    vec2 delta = waterProjectPixel(end, size) - start;
    float extent = max(max(abs(delta.x), abs(delta.y)), 0.00001);
    vec2 stepDir = delta / extent;
    float reciprocal = 1.0 / -origin.z;
    float slope = (1.0 / -end.z - reciprocal) / extent;
    // Clip against the viewport, including rays that project toward the eye.
    vec2 edge = mix(vec2(0.0), size, step(vec2(0.0), stepDir));
    vec2 edgeT = (edge - start) / (stepDir + mix(vec2(-1e-8), vec2(1e-8), step(vec2(0.0), stepDir)));
    float limit = min(extent, min(edgeT.x, edgeT.y));
    float cursor = 0.0;
    float largeExit = limit >= 64.0 ? 0.0 : limit;
    float middleExit = 0.0;
    bool hidden = false;
    for (int visit = 0; visit < 112 && cursor < limit; ++visit) {
        vec2 samplePixel = start + stepDir * min(cursor + 0.001, (cursor + limit) * 0.5);
        ivec2 pixel = clamp(ivec2(floor(samplePixel)), ivec2(0), ivec2(size) - 1);
        float next = cursor;
        bool skip = false;
        for (int level = 0; level < 3; ++level) {
            // An already overlapping tile needs no more fetches while the ray
            // is searching its children. Degenerate short rays start at 16.
            if ((level == 0 && cursor < largeExit) || (level == 1 && cursor < middleExit)) continue;
            int side = level == 0 ? 64 : (level == 1 ? 16 : 4);
            next = min(limit, waterTileExit(start, stepDir, pixel, side));
            ivec2 tile = pixel / side;
            // Fractional viewports may omit a final partial 4x4 tile.
            if (any(greaterThanEqual(tile, ivec2(size) / 4))) continue;
            if (level == 0) {
                tile.x += (int(size.x) + 15) / 16;
                largeExit = next;
                if (tile.x >= int(size.x)/4) continue;
            } else if (level == 1) {
                middleExit = next;
            }
            vec4 data = texelFetch(colortex14, tile, 0);
            vec2 bounds = level < 2 ? data.zw : data.xy;
            float z0 = 1.0 / (reciprocal + cursor * slope);
            float z1 = 1.0 / (reciprocal + next * slope);
            // Include half-float rounding and subpixel extent on steep faces.
            float margin = 0.015 + 0.002 * max(z0, z1) + (bounds.y - bounds.x) / float(min(side,16));
            skip = bounds.x > bounds.y || max(z0, z1) < bounds.x - margin
                || min(z0, z1) > bounds.y + margin;
            if (skip) {
                hidden = hidden || (bounds.x <= bounds.y && min(z0, z1) > bounds.y + margin);
                break;
            }
        }
        if (!skip) {
            next = min(limit, waterTileExit(start, stepDir, pixel, 1));
            float depth = texelFetch(depths, pixel, 0).r;
            if (depth < 0.999999) {
                vec2 centre = (vec2(pixel) + 0.5) / size;
                vec3 point = screenToView(centre, depth);
                vec3 normal = mat3(gbufferModelView) * waterBedNormal(centre, point, depths);
                float denominator = dot(normal, direction);
                float flags = texelFetch(colortex6, pixel, 0).a;
                bool cutout = flags > 2.5;
                // A labelled opaque back face exits a solid. A ray starting in
                // water must have encountered an unseen entrance before it.
                bool backFace = !cutout && fract(flags) > 0.0 && denominator >= 0.0;
                float rayZ = 1.0 / (reciprocal + 0.5 * (cursor + next) * slope);
                hidden = hidden || backFace || rayZ + point.z > max(0.008, rayZ * 0.001);
                int crease = int(round(fract(flags) * 256.0)) & 15;
                if (crease != 0 && !cutout) {
                    WaterRayHit edge = waterCreaseHit(pixel, point, normal, crease, origin, direction, range, depths, size);
                    if (edge.distance > 0.0) {
                        edge.hidden = hidden;
                        return edge;
                    }
                } else if (!backFace && abs(denominator) > 0.0001) {
                    float t = dot(normal, point - origin) / denominator;
                    if (t > 0.0005 && t <= range) {
                        vec3 intersection = origin + direction * t;
                        vec2 projected = waterProjectPixel(intersection, size);
                        // A single depth texel in an alpha-tested leaf cannot
                        // support a long surface stretched down the bank.
                        float radius = max(0.012, -point.z * abs(gbufferProjectionInverse[1][1]) * 4.0 / size.y);
                        bool supported = !cutout || length(intersection - point) <= radius;
                        if (supported && all(lessThanEqual(abs(projected - vec2(pixel) - 0.5), vec2(0.501)))) {
                            return WaterRayHit(projected / size, t, hidden);
                        }
                    }
                }
            }
        }
        cursor = max(next, cursor + 0.001);
    }
    return WaterRayHit(uv, -1.0, true);
}

// At a disocclusion or the edge of the viewport only part of the estimated
// receiver is present. Extend its plane in 3D; gather colour from the nearest
// supported part of that same plane instead of jumping to an unrelated face.
WaterRayHit waterMissingReceiver(vec2 uv, vec3 origin, vec3 ray, vec3 centre,
                                vec3 normal, sampler2D depths) {
    vec2 size = vec2(textureSize(depths, 0));
    float denominator = dot(ray, normal);
    float t = abs(denominator) > 0.001 ? dot(centre - origin, normal) / denominator : -1.0;
    if (t <= 0.0 || t > 48.0 || (origin + ray * t).z >= -near) {
        return WaterRayHit(uv, min(length(centre - origin), 48.0), true);
    }
    // In the blind region, use a nearby coplanar footprint with the same
    // world texture phase. Clamping to the viewport would stretch one row.
    vec3 point = origin + ray * t;
    vec3 n = abs(mat3(gbufferModelViewInverse) * normal);
    vec3 axisX = n.x > max(n.y, n.z) ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 axisY = n.y > max(n.x, n.z) ? vec3(0, 0, 1) : vec3(0, 1, 0);
    axisX = mat3(gbufferModelView) * axisX;
    axisY = mat3(gbufferModelView) * axisY;
    vec2 shift = round(vec2(dot(centre - point, axisX), dot(centre - point, axisY)));
    vec3 samplePoint = point + shift.x * axisX + shift.y * axisY;
    if (samplePoint.z < -near) {
        vec2 probe = waterProjectPixel(samplePoint, size) / size;
        vec2 inset = 1.0 / size;
        if (all(greaterThanEqual(probe, inset)) && all(lessThanEqual(probe, 1.0 - inset))) {
            vec2 pixel = waterBedUv(probe);
            float depth = textureLod(depths, pixel, 0.0).r;
            vec3 observed = screenToView(pixel, depth);
            if (depth < 0.999999 && abs(dot(observed - samplePoint, normal)) < max(0.018, -observed.z * 0.0005)) {
                return WaterRayHit(probe, t, true);
            }
        }
    }
    return WaterRayHit(uv, t, true);
}
