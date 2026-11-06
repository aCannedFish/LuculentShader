// Water optical stage 9: reflected radiance.
/* RENDERTARGETS: 15 */
#include "/lib/water/pipeline.glsl"

// Resolve reflection separately from refraction to keep both programs within
// native driver instruction limits. Preserve the pre-hand source underwater.
void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (isEyeInWater != 0) {
        fullOut0 = texelFetch(colortex15, pixel, 0);
        return;
    }
    fullOut0 = vec4(0.0);
    vec4 surface = waterSurfaceAtPixel(colortex9, pixel);
    if (surface.a <= 0.001 || WATER_REFLECTION_STRENGTH <= 0.0) return;
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 position = waterSurfacePosition(uv, surface.a);
    vec3 normal = waterInterfaceNormal(position, viewToAbsoluteWorld(position), surface.b);
    vec3 mirrorNormal = waterMirrorNormal(position, normal, decodeWaterNormal(surface.xy), distantWaterBlend(position));
    fullOut0 = queryWaterRadiance(position, waterAirDirection(position, mirrorNormal), WATER_ROUGHNESS, surface.b);
}
