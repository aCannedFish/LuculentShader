// Water optical stage 9: reflected radiance.
/* RENDERTARGETS: 15 */
#include "/lib/water/pipeline.glsl"
#include "/lib/reflections/bsl_water_reflection.glsl"

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
    vec3 mirrorNormal = waterMirrorNormal(position);
    vec3 direction = reflect(normalize(position), mirrorNormal);
    vec4 reflected = traceBslWaterReflection(colortex6, depthtex2, position, mirrorNormal);
    vec3 sky = waterEnvironment(viewToAbsoluteWorld(position),
        mat3(gbufferModelViewInverse) * direction, bslWaterSkyWeight(surface.b), false);
    // The BSL result is already blended with the sky. Do not run the former
    // geometry/environment fallback or reinterpret alpha as a hit distance.
    fullOut0 = vec4(mix(sky, reflected.rgb, reflected.a), 1.0);
}
