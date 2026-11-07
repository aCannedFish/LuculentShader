/* Trace the two boundaries of a thin water sheet. Parallel interfaces restore
 * the incident direction but displace the ray laterally. If the bed is reached
 * first, the same Snell ray intersects it directly. Reject foreground texels.
 */
// Bound an isolated flowing interface by the native voxel containing water.
// This is a local slab approximation; it does not infer an unseen fluid volume.
float waterSheetCellExit(vec3 position, vec3 restPosition, vec3 face, vec3 ray) {
    vec3 cell = floor(restPosition - face * 0.002);
    vec3 edge = cell + mix(vec3(0.0), vec3(1.0), greaterThan(ray, vec3(0.0)));
    vec3 distance = (edge - position) * sign(ray) / max(abs(ray), vec3(0.00001));
    distance = mix(vec3(1e20), distance, greaterThan(distance, vec3(0.0001)));
    // A vertical fall continues through the cell below. Only its cross-section
    // bounds this local water segment; a Y-grid crossing is not an air exit.
    if (abs(face.y) < 0.01) distance.y = 1e20;
    return min(min(distance.x, distance.y), min(distance.z, 1.75));
}

vec3 sampleWaterSheet(sampler2D scene, sampler2D depths, vec3 origin, vec3 normal,
                       vec3 inside, float exitT, out float pathLength) {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 size = vec2(textureSize(depths, 0));
    vec2 uv = gl_FragCoord.xy / size;
    vec3 backing = texelFetch(scene, pixel, 0).rgb;
    float depth = texelFetch(depths, pixel, 0).r;
    pathLength = exitT;
    if (depth >= 0.999999 || inside.z >= -0.001) return backing;
    vec3 bed = screenToView(uv, depth);
    if (bed.z >= origin.z) {
        pathLength = 0.0;
        return backing;
    }
    float bedT = (bed.z - origin.z) / inside.z;
    pathLength = min(bedT, exitT);
    if (WATER_REFRACTION_STRENGTH <= 0.0) return backing;
    vec3 point = origin + inside * min(bedT, exitT);
    if (bedT > exitT) {
        vec3 incident = normalize(origin);
        point += incident * ((bed.z - point.z) / incident.z);
    }
    vec2 offset = waterInterfacePixel(point, size) - gl_FragCoord.xy;
    float radius = mix(4.0, 1.5, smoothstep(8.0, 48.0, length(origin)));
    vec2 samplePixel = gl_FragCoord.xy + offset * (radius / max(radius, length(offset))) - 0.5;
    ivec2 first = ivec2(floor(samplePixel));
    vec2 f = fract(samplePixel);
    vec3 colour = vec3(0.0);
    float coverage = 0.0;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 tap = first + ivec2(x,y);
            if (any(lessThan(tap,ivec2(0))) || any(greaterThanEqual(tap,ivec2(size)))) continue;
            float z = texelFetch(depths,tap,0).r;
            if (z >= 0.999999) continue;
            vec3 observed = screenToView((vec2(tap) + 0.5) / size,z);
            if (dot(observed - origin, normal) >= 0.0 || abs(observed.z - bed.z) > max(0.35, -bed.z * 0.025)) continue;
            float weight = (x == 0 ? 1.0-f.x : f.x) * (y == 0 ? 1.0-f.y : f.y);
            colour += weight * texelFetch(scene, tap, 0).rgb;
            coverage += weight;
        }
    }
    return colour + backing * max(1.0 - coverage, 0.0);
}
