// Local and celestial illumination of rough, transparent PBR surfaces.
vec3 transparentLocalGloss(SurfaceMaterial m, vec3 normalView, vec3 tangentView, vec3 position, vec3 viewDirection, float anisotropy) {
#if defined(SIMPLE_VARYING) && (ENABLE_COLOURED_LIGHTING == 1 || GI_QUALITY > 0)
    if (!lpvHeaderValid(texelFetch(colortex8, ivec2(0), 0))) return vec3(0.0);
    vec3 normal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 tangent = normalize(mat3(gbufferModelViewInverse) * tangentView);
    vec3 view = normalize(mat3(gbufferModelViewInverse) * viewDirection);
    vec3 world = viewToAbsoluteWorld(position) + normal * 0.04;
    vec3 receiver = world - vec3(lpvOrigin(cameraPosition));
    vec3 axis = abs(normal);
    vec3 plane = axis.x >= axis.y && axis.x >= axis.z ? vec3(0.0, 1.0, 1.0)
        : axis.y >= axis.z ? vec3(1.0, 0.0, 1.0) : vec3(1.0, 1.0, 0.0);
    vec3 first = plane.x > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 second = plane.z > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 shifted = receiver - plane * 0.5;
    ivec3 base = ivec3(floor(shifted));
    vec2 fraction = vec2(dot(fract(shifted), first), dot(fract(shifted), second));
    vec3 sum = vec3(0.0);
    for (int x = 0; x < 2; x++) {
        for (int y = 0; y < 2; y++) {
            ivec3 cell = base + ivec3(first) * x + ivec3(second) * y;
            if (!lpvInside(cell)) continue;
            float weight = (x == 0 ? 1.0 - fraction.x : fraction.x)
                * (y == 0 ? 1.0 - fraction.y : fraction.y);
            ivec2 address = lpvAddress(cell);
            vec3 candidates = texelFetch(colortex10, address, 0).rgb;
            for (int entry = 0; entry < 3; entry++) {
                int identity = int(round(candidates[entry])) - 1;
                if (identity < 0) continue;
                ivec3 source = lpvCell(identity);
                uint material = lpvVoxel(source);
                if (lpvKind(material) != LPV_EMITTER) continue;
                vec3 ray = vec3(source) + vec3(0.5, 0.72, 0.5) - receiver;
                float distance = length(ray);
                vec3 colour = lpvColour(material);
                colour *= colour;
#if ENABLE_COLOURED_LIGHTING == 0
                colour = vec3(luma(colour));
#endif
                vec3 transmission = texelFetch(colortex11,
                    address + ivec2(0, entry * textureSize(colortex8, 0).y), 0).rgb;
                vec3 radiance = colour * lpvSourceEnergy(distance, lpvEmission(material)) * transmission;
                sum += materialAnisotropicSpecular(m, normal, tangent, view,
                    ray / max(distance, 0.00001), radiance, anisotropy) * weight;
            }
        }
    }
    vec3 border = vec3(lpvShape()) * 0.5 - abs(world - cameraPosition);
    return sum * smoothstep(1.0, 5.0, min(border.x, min(border.y, border.z)));
#else
    return vec3(0.0);
#endif
}

vec3 transparentDirectGloss(SurfaceMaterial m, vec3 normal, vec3 position, vec3 tangent,
                            vec3 view, vec2 lightmap, vec3 shadow) {
    float anisotropy = MATERIAL_ANISOTROPY * (1.0 - m.roughness);
    vec3 solar = materialAnisotropicSpecular(m, normal, tangent, view,
        normalize(sunPosition), getSunLightColor(), anisotropy)
        + materialAnisotropicSpecular(m, normal, tangent, view,
            normalize(moonPosition), getMoonLightColor(), anisotropy);
    float sky = smoothstep(0.60, 0.96, lightmapLevel(lightmap.y));
    solar *= shadow * sky * cloudProjectedShadow(viewToAbsoluteWorld(position),
        normalize(mat3(gbufferModelViewInverse) * getLightDirView()));
    return solar + transparentLocalGloss(m, normal, tangent, position, view, anisotropy);
}

// Return straight-alpha forward colour. Both callers composite this same
// material response after evaluating the actual sprite and lightmap.
vec4 transparentPbrLayer(LabPbrMaterial pbr, inout vec3 normal, vec3 tangent, vec3 position,
                         vec3 view, vec2 lm, float shadow, float alpha) {
    vec3 colour = computeSurfaceLighting(pbr.albedo, normal, lm, vec3(shadow), pbr.ao, position)
                + pbr.albedo * pbr.emission * ORE_GLOW_STRENGTH * 4.0;
#if ENABLE_MATERIAL_REFLECTIONS == 1
    if (max(max(pbr.f0.r, pbr.f0.g), pbr.f0.b) > 0.0001 && MATERIAL_REFLECTION_STRENGTH > 0.0) {
        normal *= dot(normal, view) >= 0.0 ? 1.0 : -1.0;
        SurfaceMaterial m = pbrBrdfMaterial(pbr);
        vec3 world = normalize(mat3(gbufferModelViewInverse) * normal);
        vec3 fresnel = materialEnvironmentWeight(m, dot(normal, view)) * MATERIAL_REFLECTION_STRENGTH;
        vec3 reflection = materialAmbientEnvironment(world, lm) * fresnel;
        reflection += transparentDirectGloss(m, normal, position, tangent, view, lm, vec3(shadow))
                    * MATERIAL_REFLECTION_STRENGTH;
        float base = clamp(alpha, 0.0, 1.0);
        alpha = base + (1.0 - base) * max(max(fresnel.r, fresnel.g), fresnel.b);
        colour = (colour * base * (1.0 - fresnel) + reflection) / max(alpha, 0.001);
    }
#endif
    return vec4(applyFog(colour, length(position)), alpha);
}
