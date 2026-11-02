/* Reuse C14 after material shading. XY contains the fine 4x4 tile,
 * ZW the range of a 16x16 tile at its own integer tile coordinate.
 */
/* RENDERTARGETS: 14 */
layout(location=0) out vec4 tile;
uniform sampler2D colortex14;

void main() {
    ivec2 cell = ivec2(gl_FragCoord.xy);
    ivec2 size = textureSize(colortex14, 0);
    vec2 coarse = vec2(65504.0, 0.0);
    if (all(lessThan(cell, (size + 15) / 16))) {
        if (any(greaterThan((cell + 1) * 16, size))) {
            coarse = vec2(0.0, 65504.0);
        } else {
            for (int y = 0; y < 4; ++y) {
                for (int x = 0; x < 4; ++x) {
                    vec2 child = texelFetch(colortex14, cell * 4 + ivec2(x, y), 0).xy;
                    coarse = vec2(min(coarse.x, child.x), max(coarse.y, child.y));
                }
            }
        }
    }
    tile = vec4(texelFetch(colortex14, cell, 0).xy, coarse);
}
