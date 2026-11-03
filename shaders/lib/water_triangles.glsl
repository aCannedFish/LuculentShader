/* Transparent rays use the exact triangles submitted to the shadow draw.
 * Macro lists only locate candidates. Barycentric triangle tests determine
 * coverage, depth and material; an occupied bin never becomes a cube surface.
 */
bool waterTrianglesReady() {
    int row = imageSize(colorimg5).y - 1;
    return waterFacesReady() && imageLoad(colorimg5,ivec2(21,row)).r > 0u
        && imageLoad(colorimg5,ivec2(22,row)).r == 0u
        && imageLoad(colorimg5,ivec2(24,row)).r != 0u;
}

vec3 waterTrianglePosition(int triangle, int vertex) {
    return uintBitsToFloat(uvec3(imageLoad(colorimg5,waterTriangleAddress(triangle,vertex * 6)).r,
        imageLoad(colorimg5,waterTriangleAddress(triangle,vertex * 6 + 1)).r,
        imageLoad(colorimg5,waterTriangleAddress(triangle,vertex * 6 + 2)).r));
}

vec3 waterTriangleNormal(uint encoded) {
    vec2 oct = unpackSnorm2x16(encoded);
    vec3 normal = vec3(oct,1.0 - abs(oct.x) - abs(oct.y));
    if (normal.z < 0.0) normal.xy = (1.0 - abs(normal.yx))
        * mix(vec2(-1.0),vec2(1.0),greaterThanEqual(normal.xy,vec2(0.0)));
    return normalize(normal);
}

// Two-sided intersection algebra retains the submitted vertex normals for
// front-face selection. The renderer may reverse a primitive's winding.
bool waterIntersectTriangle(int triangle, vec3 origin, vec3 ray, float low, float high,
                            out float distance, out vec3 barycentric) {
    vec3 a = waterTrianglePosition(triangle,0);
    vec3 e1 = waterTrianglePosition(triangle,1) - a;
    vec3 e2 = waterTrianglePosition(triangle,2) - a;
    vec3 crossRay = cross(ray,e2);
    float det = dot(e1,crossRay);
    if (abs(det) < 1e-9) return false;
    vec3 relative = origin - a;
    float u = dot(relative,crossRay) / det;
    if (u < -0.000001 || u > 1.000001) return false;
    vec3 q = cross(relative,e1);
    float v = dot(ray,q) / det;
    if (v < -0.000001 || u + v > 1.000001) return false;
    distance = dot(e2,q) / det;
    if (distance <= low || distance > high) return false;
    vec3 normal = waterTriangleNormal(imageLoad(colorimg5,waterTriangleAddress(triangle,5)).r);
    if (dot(normal,ray) >= -0.00001) return false;
    barycentric = vec3(1.0 - u - v,u,v);
    return true;
}

// Find the nearest submitted triangle in front of a distance threshold. Each
// macro is visited once, and repeated list membership cannot create layers.
int waterNextTriangle(vec3 position, vec3 direction, float low, float high,
                      out float distance, out vec3 barycentric) {
    vec3 origin = viewToWorld(position) + fract(cameraPosition);
    vec3 gridOrigin = origin + vec3(waterFarSize) * 0.5;
    vec3 ray = mat3(gbufferModelViewInverse) * direction;
    bvec3 parallel = lessThan(abs(ray),vec3(1e-8));
    if (any(bvec3(parallel.x && (gridOrigin.x < 0.0 || gridOrigin.x >= float(waterFarSize.x)),
                  parallel.y && (gridOrigin.y < 0.0 || gridOrigin.y >= float(waterFarSize.y)),
                  parallel.z && (gridOrigin.z < 0.0 || gridOrigin.z >= float(waterFarSize.z))))) return -1;
    vec3 inverseRay = sign(ray) / max(abs(ray),vec3(1e-8));
    vec3 a = -gridOrigin * inverseRay;
    vec3 b = (vec3(waterFarSize) - gridOrigin) * inverseRay;
    vec3 entry = mix(min(a,b),vec3(-1e8),parallel);
    vec3 leave = mix(max(a,b),vec3(1e8),parallel);
    float cursor = max(low,max(entry.x,max(entry.y,entry.z)));
    float limit = min(high,min(leave.x,min(leave.y,leave.z)));
    ivec3 macro = clamp(ivec3(floor(fma(ray,vec3(cursor + 0.00001),gridOrigin) / 4.0)),ivec3(0),waterMacroSize - 1);
    for (int visit = 0; visit < 96 && cursor < limit; ++visit) {
        vec3 border = vec3(macro + ivec3(greaterThanEqual(ray,vec3(0.0)))) * 4.0;
        vec3 times = mix((border - gridOrigin) * inverseRay,vec3(1e8),parallel);
        float next = min(limit,min(times.x,min(times.y,times.z)));
        int index = macro.x + waterMacroSize.x * (macro.y + waterMacroSize.y * macro.z);
        uint link = imageLoad(colorimg5,waterTriangleHead(index)).r;
        int selected = -1;
        distance = next + 0.00001;
        while (link > 0u && link <= uint(waterTriangleNodes)) {
            int node = int(link - 1u);
            int triangle = int(imageLoad(colorimg5,waterTriangleLink(node,1)).r);
            link = imageLoad(colorimg5,waterTriangleLink(node,0)).r;
            if (triangle < 0 || triangle >= waterTriangleSlots) continue;
            float candidate;
            vec3 bary;
            if (waterIntersectTriangle(triangle,origin,ray,max(low,cursor - 0.00002),distance,candidate,bary)) {
                selected = triangle;
                distance = candidate;
                barycentric = bary;
            }
        }
        if (selected >= 0) return selected;
        cursor = max(next,cursor + 0.00001);
        if (cursor >= limit) break;
        bvec3 crossed = lessThanEqual(times,vec3(next + 0.00001));
        macro += ivec3(crossed) * ivec3(sign(ray));
        if (any(lessThan(macro,ivec3(0))) || any(greaterThanEqual(macro,waterMacroSize))) break;
    }
    return -1;
}

// Restore UVs, smooth normals and colour/lightmap/alpha from the actual three
// vertices. Their UV Jacobian supplies texture directions and the POM frame.
vec4 waterTriangleRadiance(int triangle, vec3 barycentric, vec3 hitView, vec3 view) {
    vec3 point[3];
    vec2 corner[3];
    vec2 uv = vec2(0.0);
    vec2 low = vec2(1.0);
    vec2 high = vec2(0.0);
    vec3 tint = vec3(0.0);
    vec3 normal = vec3(0.0);
    vec2 lm = vec2(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 3; ++i) {
        point[i] = waterTrianglePosition(triangle,i);
        corner[i] = unpackUnorm2x16(imageLoad(colorimg5,waterTriangleAddress(triangle,i * 6 + 3)).r);
        uint data = imageLoad(colorimg5,waterTriangleAddress(triangle,i * 6 + 4)).r;
        float weight = barycentric[i];
        uv += corner[i] * weight;
        low = min(low,corner[i]);
        high = max(high,corner[i]);
        tint += weight * vec3(data & 31u,(data >> 5u) & 63u,(data >> 11u) & 31u) / vec3(31,63,31);
        uint opacity = ((data >> 16u) & 15u) | ((data >> 24u) & 240u);
        alpha += weight * float(opacity) / 255.0;
        lm += weight * vec2((data >> 20u) & 15u,(data >> 24u) & 15u);
        normal += weight * waterTriangleNormal(imageLoad(colorimg5,waterTriangleAddress(triangle,i * 6 + 5)).r);
    }
    vec3 e1 = point[1] - point[0];
    vec3 e2 = point[2] - point[0];
    vec2 du = corner[1] - corner[0];
    vec2 dv = corner[2] - corner[0];
    float determinant = du.x * dv.y - du.y * dv.x;
    vec3 geometric = normalize(mat3(gbufferModelView) * normal);
    vec3 tangent = mat3(gbufferModelView) * (e1 * dv.y - e2 * du.y) * sign(determinant);
    vec3 bitangent = mat3(gbufferModelView) * (e2 * du.x - e1 * dv.x) * sign(determinant);
    tangent = safeNormalize(tangent,cross(geometric,abs(geometric.y) < 0.9 ? vec3(0,1,0) : vec3(1,0,0)));
    bitangent = safeNormalize(bitangent,cross(geometric,tangent));
    vec3 plane = cross(e1,e2);
    float area = dot(e1,cross(e2,plane));
    vec3 along = (cross(e2,plane) * du.x + cross(plane,e1) * dv.x) / max(area,1e-12);
    vec3 across = (cross(e2,plane) * du.y + cross(plane,e1) * dv.y) / max(area,1e-12);
    float footprint = 2.0 * abs(hitView.z * gbufferProjectionInverse[1][1]) / max(viewHeight,1.0);
    vec2 gx = vec2(length(along),0.0) * footprint;
    vec2 gy = vec2(0.0,length(across)) * footprint;
    return waterShadeGlass(uv,low,high,tangent,bitangent,geometric,gx,gy,hitView,view,
        (lm + 0.5) / 16.0,tint,alpha,abs(determinant) > 1e-12);
}

// Discard the camera aggregate only when its nearest measured point belongs
// to a recorded triangle. This prevents double opacity at a pane silhouette.
bool waterTriangleOwnsRaster(vec2 uv) {
    vec4 layer = texelFetch(colortex7,ivec2(uv * vec2(viewWidth,viewHeight)),0);
    if (layer.a < 0.5 || layer.b <= 0.0) return false;
    vec3 point = waterSurfacePosition(uv,layer.b);
    float lengthToPoint = length(point);
    vec3 direction = point / lengthToPoint;
    float tolerance = max(0.003,abs(point.z) * 0.0015);
    float distance;
    vec3 barycentric;
    return waterNextTriangle(vec3(0.0),direction,max(0.0,lengthToPoint - tolerance),
        lengthToPoint + tolerance,distance,barycentric) >= 0;
}

vec4 waterTriangleLayers(vec3 position, vec3 direction, float range, float opaqueLimit, WaterRayHit cameraLayer) {
    vec4 colour = vec4(0.0);
    bool useCamera = cameraLayer.distance > 0.0 && cameraLayer.distance < opaqueLimit
        && !waterTriangleOwnsRaster(cameraLayer.uv);
    float cursor = 0.0001;
    for (int layer = 0; layer < 32 && colour.a < 0.9999; ++layer) {
        float distance;
        vec3 barycentric;
        int triangle = waterNextTriangle(position,direction,cursor,range,distance,barycentric);
        if (triangle < 0) break;
        if (useCamera && cameraLayer.distance <= distance + 0.001) {
            appendWaterLayer(colour,waterScreenLayer(cameraLayer.uv));
            useCamera = false;
        }
        appendWaterLayer(colour,waterTriangleRadiance(triangle,barycentric,position + direction * distance,-direction));
        cursor = distance + max(0.0001,distance * 0.000002);
    }
    if (useCamera) appendWaterLayer(colour,waterScreenLayer(cameraLayer.uv));
    return colour;
}
