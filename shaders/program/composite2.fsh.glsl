/* Linear view-depth bounds over native opaque samples. Empty sky tiles
 * have reversed bounds and can be skipped without a fictitious far surface.
 */
/* RENDERTARGETS: 14 */
layout(location=0) out vec4 tile;
uniform sampler2D depthtex2;
uniform sampler2D colortex7;
uniform int isEyeInWater;
uniform mat4 gbufferProjectionInverse;

void main() {
    ivec2 first = ivec2(gl_FragCoord.xy) * 4;
    vec2 bounds = vec2(65504.0, 0.0);
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            ivec2 pixel = first + ivec2(x, y);
            float depth = texelFetch(depthtex2, pixel, 0).r;
            if (depth < 0.999999) {
                vec4 point = gbufferProjectionInverse * vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
                float z = -point.z / point.w;
                bounds = vec2(min(bounds.x, z), max(bounds.y, z));
            }
            if (isEyeInWater == 1) {
                vec4 layer = texelFetch(colortex7, pixel, 0);
                if (layer.a > 0.5 && layer.b > 0.0) {
                    bounds = vec2(min(bounds.x, layer.b), max(bounds.y, layer.b));
                }
            }
        }
    }
    tile = vec4(bounds, 0.0, 0.0);
}
