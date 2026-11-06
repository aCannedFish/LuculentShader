// Water optical stage 10: transmitted radiance.
/* RENDERTARGETS: 7 */
#include "/lib/water/pipeline.glsl"

// Save one shaded receiver per water pixel. The composition pass integrates
// their coverage before applying this pixel's Fresnel, fog and weather.
void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
#if SIMPLE_DIMENSION == 0
    if (isEyeInWater == 0 && all(lessThan(pixel,ivec2(waterEnvironmentSide)))) updateWaterEnvironment(pixel);
#endif
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 surface = waterSurfaceAtPixel(colortex9, ivec2(gl_FragCoord.xy));
    fullOut1 = vec4(0.0);
    if (isEyeInWater == 1) {
        fullOut0 = texelFetch(colortex7, pixel, 0);
        return;
    }
    if (isEyeInWater != 0 || surface.a <= 0.001) {
        fullOut0 = vec4(0.0);
        return;
    }
    vec3 position = waterSurfacePosition(uv, surface.a);
    vec3 normal = waterInterfaceNormal(position, viewToAbsoluteWorld(position), surface.b);
    float lod = distantWaterBlend(position);
    ivec2 last = textureSize(colortex9, 0) - 1;
    ivec2 anchor = distantWaterAnchor(pixel / distantWaterStride, last);
    bool representative = all(equal(pixel, anchor));
    if (lod >= 1.0 && !representative && distantWaterSupports(anchor, position)) {
        fullOut0 = vec4(0.0);
        return;
    }
    vec4 scattering = texelFetch(colortex7, pixel, 0);
    if (lod >= 1.0) {
        fullOut0 = vec4(distantWaterBed(uv, position, normal, scattering.rgb), 0.0);
        return;
    }
    float tag;
    vec3 colour = transmitWaterSample(uv, position, normal, surface, scattering, tag);
    if (representative && lod > 0.0) {
        colour = mix(colour, distantWaterBed(uv, position, normal, scattering.rgb), lod);
    }
    fullOut0 = vec4(colour, tag);
}
