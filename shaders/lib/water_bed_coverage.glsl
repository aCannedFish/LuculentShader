// A near, opaque unit face can be shared by neighbouring refracted rays.
// Store its orientation, plane modulo 64 and tangent coordinates modulo 8
// in an exactly representable, normal half float in the transmission buffer.
float waterBedFaceTag(vec3 point, vec3 normal, float distance) {
    if (WATER_REFRACTION_STRENGTH <= 0.0 || distance <= 0.0 || distance >= 24.0 || !waterFacesReady()) return 0.0;
    vec3 magnitude = abs(normal);
    int axis = magnitude.x > max(magnitude.y, magnitude.z) ? 0 : (magnitude.y > magnitude.z ? 1 : 2);
    if (magnitude[axis] < 0.9999) return 0.0;
    ivec3 owner = ivec3(floor(point - normal * 0.004));
    bool negative = normal[axis] < 0.0;
    int plane = owner[axis] + int(!negative);
    if (abs(point[axis] - float(plane)) > 0.006) return 0.0;
    int face = waterFindFace(owner, axis, negative, false);
    if (face < 0 || imageLoad(colorimg5, waterFaceAddress(face, 2)).r != 15u
        || imageLoad(colorimg5, waterFaceAddress(face, 3)).r != 0u
        || (imageLoad(colorimg5, waterFaceAddress(face, 8)).r >> 28u) != 0u) return 0.0;
    int u = (axis + 1) % 3;
    int v = (axis + 2) % 3;
    int key = ((2 * axis + int(negative)) * 64 + (plane & 63)) * 64
        + (owner[u] & 7) * 8 + (owner[v] & 7);
    return unpackHalf2x16(uint(1024 + key)).x;
}

struct WaterBedPatch {
    vec2 centre;
    vec2 dx;
    vec2 dy;
    vec3 depth; // t at the pixel centre, dt/dx, dt/dy
    float weight;
};

// Recover the nearby integer rectangle and the differential of the Snell
// ray's intersection with its plane. Tangent coordinates are relative to
// the centre of the face so the four clipping bounds are always +/- 0.5.
WaterBedPatch waterProjectBedPatch(float tag, vec3 origin, vec3 ray, vec3 ox, vec3 oy, vec3 rx, vec3 ry) {
    int key = int(packHalf2x16(vec2(tag, 0.0)) & 65535u) - 1024;
    int face = key >> 12;
    int axis = face >> 1;
    int u = (axis + 1) % 3;
    int v = (axis + 2) % 3;
    float plane = float((key >> 6) & 63);
    plane += 64.0 * round((origin[axis] - plane) / 64.0);
    WaterBedPatch invalid = WaterBedPatch(vec2(0), vec2(0), vec2(0), vec3(-1.0), 0.0);
    if (ray[axis] * ((face & 1) == 0 ? 1.0 : -1.0) >= -0.001) return invalid;
    float t = (plane - origin[axis]) / ray[axis];
    if (t <= 0.0 || t > 25.0) return invalid;
    vec3 point = origin + t * ray;
    vec3 hx = ox + t * rx;
    vec3 hy = oy + t * ry;
    vec2 dt = -vec2(hx[axis], hy[axis]) / ray[axis];
    hx += ray * dt.x;
    hy += ray * dt.y;
    float footprint = max(length(hx), length(hy));
    if (footprint >= 1.0) return invalid;
    vec2 middle = vec2((key >> 3) & 7, key & 7) + 0.5;
    vec2 tangent = vec2(point[u], point[v]);
    middle += 8.0 * round((tangent - middle) / 8.0);
    // Lose the correction gradually before a distant or grazing face drops
    // out of the packet, including at the edge of the native capture volume.
    vec3 local = point - vec3(waterFarOrigin());
    vec3 margin = min(local, vec3(waterFarSize) - local);
    float weight = (1.0 - smoothstep(18.0, 24.0, t)) * (1.0 - smoothstep(0.5, 1.0, footprint))
                 * smoothstep(0.0, 2.0, min(margin.x, min(margin.y, margin.z)));
    return WaterBedPatch(tangent - middle, vec2(hx[u], hx[v]), vec2(hy[u], hy[v]), vec3(t, dt), weight);
}

// Integrate one straight cut through a square pixel. The projection of a
// uniform square onto the edge normal has a trapezoidal density.
float waterStraightArea(WaterBedPatch surface, out vec2 direction) {
    direction = vec2(0.0);
    float area = 1.0;
    for (int i = 0; i < 2; ++i) {
        vec2 gradient = vec2(surface.dx[i], surface.dy[i]);
        vec2 width = abs(gradient);
        float extent = 0.5 * (width.x + width.y);
        float gap = 0.5 - abs(surface.centre[i]);
        if (gap <= -extent) return 0.0;
        if (gap >= extent) continue;
        if (area < 1.0) return -1.0; // Two bounds cut this pixel at a corner.
        direction = normalize(gradient) * sign(surface.centre[i]);
        float major = max(width.x, width.y);
        float minor = min(width.x, width.y);
        if (abs(gap) <= 0.5 * (major - minor)) {
            area = 0.5 + gap / major;
        } else {
            float tail = extent - abs(gap);
            float cap = tail * tail / (2.0 * major * minor);
            area = gap < 0.0 ? cap : 1.0 - cap;
        }
    }
    return area;
}

// Shade each resolved surface once. Integrate the projected area of the actual
// rectangles, keeping the background's attenuation when a subray misses a ledge.
vec3 waterResolveBed(vec2 uv, vec3 position, vec3 opticalNormal, vec4 centre) {
    float eta = 1.0 / mix(1.0, WATER_IOR, WATER_REFRACTION_STRENGTH);
    vec3 origin = viewToAbsoluteWorld(position);
    vec3 ray = mat3(gbufferModelViewInverse) * refract(normalize(position), opticalNormal, eta);
    vec3 ox = dFdx(origin);
    vec3 oy = dFdy(origin);
    vec3 rx = dFdx(ray);
    vec3 ry = dFdy(ray);
    if (centre.a == 0.0 || max(length(ox), length(oy)) > 0.5) return centre.rgb;

    const ivec2 offsets[8] = ivec2[8](ivec2(-1,0), ivec2(1,0), ivec2(0,-1), ivec2(0,1),
        ivec2(-1,-1), ivec2(-1,1), ivec2(1,-1), ivec2(1,1));
    ivec2 pixel = ivec2(uv * vec2(viewWidth, viewHeight));
    ivec2 limit = textureSize(colortex7, 0) - 1;
    vec4 samples[9];
    samples[0] = centre;
    int count = 1;
    for (int tap = 0; tap < 8; ++tap) {
        vec4 other = texelFetch(colortex7, clamp(pixel + offsets[tap], ivec2(0), limit), 0);
        if (other.a == 0.0 || other.a == centre.a) continue;
        bool known = false;
        for (int j = 1; j < count; ++j) known = known || samples[j].a == other.a;
        if (!known) samples[count++] = other;
    }
    if (count == 1) return centre.rgb;

    WaterBedPatch first = waterProjectBedPatch(centre.a, origin, ray, ox, oy, rx, ry);
    if (first.weight <= 0.0) return centre.rgb;
    float nearWeight = first.weight;
    if (count == 2) {
        WaterBedPatch other = waterProjectBedPatch(samples[1].a, origin, ray, ox, oy, rx, ry);
        if (other.weight <= 0.0) return centre.rgb;
        vec2 edgeA, edgeB;
        float a = waterStraightArea(first, edgeA);
        float b = waterStraightArea(other, edgeB);
        float alignment = dot(edgeA, edgeB);
        if (a >= 0.0 && b >= 0.0 && (a * b == 0.0 || a == 1.0 || b == 1.0 || abs(alignment) > 0.99999)) {
            float overlap = alignment < 0.0 ? max(a + b - 1.0, 0.0) : min(a, b);
            float visible = (other.depth.x < first.depth.x ? b : b - overlap) * other.weight;
            return mix(centre.rgb, samples[1].rgb, clamp(visible * nearWeight, 0.0, 1.0));
        }
    }

    // Corners and overlapping nonparallel edges use eight stratified ray
    // locations. Select the nearest covered face at each location.
    float distances[8];
    int selected[8];
    for (int k = 0; k < 8; ++k) {
        distances[k] = 49.0;
        selected[k] = 0;
    }
    const vec2 pattern[8] = vec2[8](vec2(-7,-1), vec2(-5,5), vec2(-3,-5), vec2(-1,1),
        vec2(1,-3), vec2(3,7), vec2(5,-7), vec2(7,3));
    for (int j = 0; j < count; ++j) {
        WaterBedPatch patchFace = waterProjectBedPatch(samples[j].a, origin, ray, ox, oy, rx, ry);
        if (patchFace.depth.x <= 0.0) continue;
        samples[j].rgb = mix(centre.rgb, samples[j].rgb, patchFace.weight);
        for (int k = 0; k < 8; ++k) {
            vec2 q = pattern[k] / 16.0;
            float depth = dot(patchFace.depth, vec3(1.0, q));
            vec2 hit = patchFace.centre + q.x * patchFace.dx + q.y * patchFace.dy;
            if (depth <= 0.0 || depth >= distances[k]) continue;
            if (any(greaterThan(abs(hit), vec2(0.5)))) continue;
            distances[k] = depth;
            selected[k] = j;
        }
    }
    vec3 sum = vec3(0.0);
    for (int k = 0; k < 8; ++k) sum += samples[selected[k]].rgb;
    return mix(centre.rgb, sum * 0.125, nearWeight);
}
