// Resolve the underwater exit before the independent air-side water programs.
/* RENDERTARGETS: 7 */
#include "/lib/water/native_optics.glsl"
#include "/lib/water/underwater.glsl"

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (isEyeInWater == 1) {
        vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        fullOut0 = applyUnderwaterOptics(uv);
        return;
    }
    // Preserve forward water scattering until air-side transmission consumes it.
    fullOut0 = texelFetch(colortex7, pixel, 0);
}
