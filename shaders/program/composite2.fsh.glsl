/* Linear view-depth bounds over native opaque samples. Empty sky tiles
 * have reversed bounds and can be skipped without a fictitious far surface.
 */
/* RENDERTARGETS: 14 */
layout(location=0) out vec4 tile;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjectionInverse;

void main() {
    ivec2 first = ivec2(gl_FragCoord.xy) * 4;
    vec2 bounds = vec2(65504.0, 0.0);
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            float depth = texelFetch(depthtex1, first + ivec2(x, y), 0).r;
            if (depth < 0.999999) {
                vec4 point = gbufferProjectionInverse * vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
                float z = -point.z / point.w;
                bounds = vec2(min(bounds.x, z), max(bounds.y, z));
            }
        }
    }
    tile = vec4(bounds, 0.0, 0.0);
}
