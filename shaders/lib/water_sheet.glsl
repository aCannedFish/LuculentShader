/* Trace the two boundaries of a thin water sheet. Parallel interfaces restore
 * the incident direction but displace the ray laterally. If the bed is reached
 * first, the same Snell ray intersects it directly. Reject foreground texels.
 */
vec3 waterSheetTransmission(sampler2D scene, sampler2D depths, vec3 origin, vec3 normal,
                            vec3 inside, float thickness, out vec3 backing) {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 size = vec2(textureSize(depths, 0));
    vec2 uv = gl_FragCoord.xy / size;
    backing = texelFetch(scene, pixel, 0).rgb;
    float depth = texelFetch(depths, pixel, 0).r;
    if (depth >= 0.999999 || WATER_REFRACTION_STRENGTH <= 0.0 || inside.z >= -0.001) return vec3(0.0);
    vec3 bed = screenToView(uv, depth);
    if (bed.z >= origin.z) return vec3(0.0);
    float bedT = (bed.z - origin.z) / inside.z;
    float exitT = thickness / max(0.1, -dot(inside, normal));
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
    vec3 difference = vec3(0.0);
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 tap = first + ivec2(x,y);
            if (any(lessThan(tap,ivec2(0))) || any(greaterThanEqual(tap,ivec2(size)))) continue;
            float z = texelFetch(depths,tap,0).r;
            if (z >= 0.999999) continue;
            vec3 observed = screenToView((vec2(tap) + 0.5) / size,z);
            if (dot(observed - origin, normal) >= 0.0 || abs(observed.z - bed.z) > max(0.35, -bed.z * 0.025)) continue;
            float weight = (x == 0 ? 1.0-f.x : f.x) * (y == 0 ? 1.0-f.y : f.y);
            difference += weight * (texelFetch(scene,tap,0).rgb - backing);
        }
    }
    return difference;
}
