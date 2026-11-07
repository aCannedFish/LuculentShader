/* Record only submitted transparent triangles, with their real connectivity,
 * before shadow rasterization. Ordinary shadow primitives pass through once.
 */
#include "/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/water_face_cache.glsl"
#include "/lib/water_entity_triangles.glsl"
#include "/lib/water_plant_surface.glsl"
#include "/lib/water_waves.glsl"
layout(triangles) in;
layout(triangle_strip, max_vertices=3) out;

in vec2 gTexCoord[];
in vec4 gColor[];
in vec3 gShadowPosition[];
in vec3 gCasterNormal[];
in vec2 gCasterLight[];
flat in int gWaterFaceParity[];
in float gCaster[];
in vec3 gNativePosition[];
flat in int gTransparentTriangle[];

out vec2 vTexCoord;
out vec4 vColor;
out vec3 vShadowPosition;
out vec3 vCasterNormal;
out vec2 vCasterLight;
flat out int vWaterFaceParity;
out float vCaster;
flat out int vEntityTriangle;
uniform sampler2D gtexture;
uniform vec4 spriteBounds;
uniform sampler2D gaux4;
uniform sampler2D colortex14;

// The loader forces shadow blending off, so blendFunc cannot identify glint.
// Compare the submitted texture to the engine's current glint sprites instead;
// resource-pack replacements follow the same references without hardcoded hues.
bool shadowGlintTexture(sampler2D reference) {
    ivec2 size = textureSize(gtexture, 0);
    if (any(notEqual(size, textureSize(reference, 0)))) return false;
    for (int sampleIndex = 0; sampleIndex < 16; ++sampleIndex) {
        vec2 point = fract(vec2(0.37, 0.61) + float(sampleIndex) * vec2(0.381966, 0.618034));
        ivec2 pixel = min(ivec2(point * vec2(size)), size - 1);
        if (any(notEqual(texelFetch(gtexture, pixel, 0), texelFetch(reference, pixel, 0)))) return false;
    }
    return true;
}

// Store smooth normals separately from triangle positions. The latter retain
// the actual surface; normal maps and vertex normals only affect illumination.
uint waterTriangleEncodeNormal(vec3 value) {
    value = normalize(value);
    value /= abs(value.x) + abs(value.y) + abs(value.z);
    vec2 oct = value.xy;
    if (value.z < 0.0) oct = (1.0 - abs(oct.yx)) * mix(vec2(-1.0), vec2(1.0), greaterThanEqual(oct, vec2(0.0)));
    return packSnorm2x16(oct);
}

// A fast rectangle is allowed only after its two actual triangle halves and
// original corner attributes have been checked. Record the submitted half here;
// the compute stage validates the complete face after all shadow draws finish.
uvec2 waterTriangleUnitFace() {
    vec3 normal = normalize(gCasterNormal[0]);
    vec3 magnitude = abs(normal);
    int axis = magnitude.x > max(magnitude.y,magnitude.z) ? 0 : (magnitude.y > magnitude.z ? 1 : 2);
    if (magnitude[axis] < 0.99999) return uvec2(0u);
    if (dot(normal,normalize(gCasterNormal[1])) < 0.99999
        || dot(normal,normalize(gCasterNormal[2])) < 0.99999) return uvec2(0u);
    vec3 centre = (gNativePosition[0] + gNativePosition[1] + gNativePosition[2]) / 3.0;
    ivec3 owner = ivec3(floor(centre + floor(cameraPosition) - normal * 0.01));
    uint corners = 0u;
    uint indices = 0u;
    for (int i = 0; i < 3; ++i) {
        vec3 local = gNativePosition[i] + (floor(cameraPosition) - vec3(owner)) - 0.5;
        if (any(greaterThan(abs(abs(local) - 0.5),vec3(0.0001)))) return uvec2(0u);
        if (abs(local[axis] - sign(normal[axis]) * 0.5) > 0.0001) return uvec2(0u);
        vec2 tangent = waterFaceAxes(local,axis);
        uint corner = uint(int(tangent.x > 0.0) + 2 * int(tangent.y > 0.0));
        corners |= 1u << corner;
        indices |= corner << uint(i * 2);
    }
    uint missing = 15u & ~corners;
    if (bitCount(missing) != 1) return uvec2(0u);
    int face = waterFindFace(owner,axis,normal[axis] < 0.0,true,true);
    if (face < 0) return uvec2(0u);
    imageAtomicOr(colorimg5,waterFaceAddress(face,12),missing);
    return uvec2(uint(face + 1),indices);
}

void captureWaterTriangle() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (WATER_REFRACTION_STRENGTH <= 0.0) return;
    if (gTransparentTriangle[0] == 0 || gTransparentTriangle[1] == 0 || gTransparentTriangle[2] == 0) return;
    vec3 low = min(gNativePosition[0], min(gNativePosition[1], gNativePosition[2])) + vec3(waterFarSize) * 0.5;
    vec3 high = max(gNativePosition[0], max(gNativePosition[1], gNativePosition[2])) + vec3(waterFarSize) * 0.5;
    if (any(lessThan(high, vec3(0.0))) || any(greaterThanEqual(low, vec3(waterFarSize)))) return;
    if (length(cross(gNativePosition[1] - gNativePosition[0], gNativePosition[2] - gNativePosition[0])) < 1e-8) return;
    int row = imageSize(colorimg5).y - 1;
    uint triangle = imageAtomicAdd(colorimg5, ivec2(21,row), 1u);
    if (triangle >= uint(waterTriangleSlots)) {
        imageAtomicOr(colorimg5, ivec2(22,row), 1u);
        return;
    }
    vec2 extent = spriteBounds.zw - spriteBounds.xy;
    bool single = all(greaterThan(extent, vec2(0.0))) && any(notEqual(textureSize(gtexture,0), atlasSize));
    for (int i = 0; i < 3; ++i) {
        vec3 position = gNativePosition[i];
        vec2 uv = single ? spriteBounds.xy + gTexCoord[i] * extent : gTexCoord[i];
        uvec3 colour = uvec3(round(clamp(gColor[i].rgb, 0.0, 1.0) * vec3(31,63,31)));
        uint alpha = uint(round(clamp(gColor[i].a,0.0,1.0) * 255.0));
        uvec2 lm = uvec2(round(clamp(gCasterLight[i],0.0,1.0) * 15.0));
        uint attributes = colour.x | (colour.y << 5u) | (colour.z << 11u)
            | ((alpha & 15u) << 16u) | (lm.x << 20u) | (lm.y << 24u) | ((alpha >> 4u) << 28u);
        for (int axis = 0; axis < 3; ++axis) imageStore(colorimg5, waterTriangleAddress(int(triangle), i * 6 + axis), uvec4(floatBitsToUint(position[axis])));
        imageStore(colorimg5, waterTriangleAddress(int(triangle), i * 6 + 3), uvec4(packUnorm2x16(uv)));
        imageStore(colorimg5, waterTriangleAddress(int(triangle), i * 6 + 4), uvec4(attributes));
        imageStore(colorimg5, waterTriangleAddress(int(triangle), i * 6 + 5), uvec4(waterTriangleEncodeNormal(gCasterNormal[i])));
    }
    uvec2 unit = waterTriangleUnitFace();
    imageStore(colorimg5,waterTriangleAddress(int(triangle),18),uvec4(unit.x));
    imageStore(colorimg5,waterTriangleAddress(int(triangle),19),uvec4(unit.y));
    // Conservative macro bins accelerate queries. Every accepted hit still
    // intersects the recorded triangle and interpolates its original vertices.
    ivec3 first = clamp(ivec3(floor((low - 0.0001) / 4.0)), ivec3(0), waterMacroSize - 1);
    ivec3 last = clamp(ivec3(floor((high + 0.0001) / 4.0)), ivec3(0), waterMacroSize - 1);
    for (int z = first.z; z <= last.z; ++z) {
        for (int y = first.y; y <= last.y; ++y) {
            for (int x = first.x; x <= last.x; ++x) {
                uint node = imageAtomicAdd(colorimg5, ivec2(23,row), 1u);
                if (node >= uint(waterTriangleNodes)) {
                    imageAtomicOr(colorimg5, ivec2(22,row), 2u);
                    return;
                }
                int macro = x + waterMacroSize.x * (y + waterMacroSize.y * z);
                uint previous = imageAtomicExchange(colorimg5, waterTriangleHead(macro), node + 1u);
                imageStore(colorimg5, waterTriangleLink(int(node),0), uvec4(previous));
                imageStore(colorimg5, waterTriangleLink(int(node),1), uvec4(triangle));
            }
        }
    }
    ivec3 lowerCell = clamp(ivec3(floor(low)), ivec3(0), waterFarSize - 1);
    ivec3 upperCell = clamp(ivec3(floor(high)), ivec3(0), waterFarSize - 1);
    for (int axis = 0; axis < 3; ++axis) {
        int scale = waterFarSize[axis] / 32;
        uint lo = 0xffffffffu << uint(lowerCell[axis] / scale);
        uint hi = 0xffffffffu >> uint(31 - upperCell[axis] / scale);
        imageAtomicOr(colorimg5, ivec2(18 + axis,row), lo & hi);
    }
#endif
}

// Retain a conservative top height. Checking all four lattice corners keeps
// both halves of a water quad below the same wave trough bound.
void capturePlantWaterSurface() {
#if SIMPLE_DIMENSION == 0
    if (isEyeInWater == 1 || abs(gCaster[0] - 3.0) > 0.1 || gCasterNormal[0].y < 0.9) return;
    vec3 centre = (gNativePosition[0] + gNativePosition[1] + gNativePosition[2]) / 3.0 + floor(cameraPosition);
    int index = waterPlantColumn(centre.xz);
    if (index < 0) return;
    float height = 1e6;
    for (int i = 0; i < 3; ++i) {
        vec3 point = gNativePosition[i] + floor(cameraPosition);
        height = min(height, point.y);
    }
#if ENABLE_WATER_WAVES == 1
    vec2 cell = floor(centre.xz);
    float wave = min(getWaterWaveHeight(cell, frameTimeCounter),
        getWaterWaveHeight(cell + vec2(1.0, 0.0), frameTimeCounter));
    wave = min(wave, getWaterWaveHeight(cell + vec2(0.0, 1.0), frameTimeCounter));
    wave = min(wave, getWaterWaveHeight(cell + vec2(1.0), frameTimeCounter));
    // Distant crests converge to the fluid rest height as their footprint grows.
    height += min(wave, 0.0);
#endif
    imageAtomicMax(colorimg5, waterPlantAddress(index), floatBitsToUint(height + 4096.0));
#endif
}

// Preserve actor mesh connectivity before rasterization. The fragment record
// references this exact triangle even when it is smaller than a shadow texel.
int captureWaterEntityTriangle() {
#if SIMPLE_DIMENSION == 0 && ENABLE_SHADOWS == 1
    if (isTerrainStage()) return -1;
    vec3 area = cross(gNativePosition[1] - gNativePosition[0], gNativePosition[2] - gNativePosition[0]);
    if (dot(area, area) < 1e-16) return -1;
    uint index = imageAtomicAdd(colorimg5, ivec2(29, imageSize(colorimg5).y - 1), 1u);
    if (index >= uint(waterEntityCapacity)) return -1;
    for (int vertex = 0; vertex < 3; ++vertex) {
        for (int axis = 0; axis < 3; ++axis) {
            imageStore(colorimg5, waterEntityAddress(int(index), vertex * 3 + axis),
                uvec4(floatBitsToUint(gNativePosition[vertex][axis])));
        }
    }
    return int(index);
#else
    return -1;
#endif
}

void main() {
    // Enchantment glint is a colour overlay on an existing actor surface.
    // Its SRC_COLOR/ONE blend must not replace opaque depth/material records.
    if ((isActorStage())
        && (shadowGlintTexture(gaux4) || shadowGlintTexture(colortex14))) return;
    int entityTriangle = captureWaterEntityTriangle();
    capturePlantWaterSurface();
    captureWaterTriangle();
    for (int i = 0; i < 3; ++i) {
        gl_Position = gl_in[i].gl_Position;
        gl_PrimitiveID = gl_PrimitiveIDIn;
        vTexCoord = gTexCoord[i];
        vColor = gColor[i];
        vShadowPosition = gShadowPosition[i];
        vCasterNormal = gCasterNormal[i];
        vCasterLight = gCasterLight[i];
        vWaterFaceParity = gWaterFaceParity[i];
        vCaster = gCaster[i];
        vEntityTriangle = entityTriangle;
        EmitVertex();
    }
    EndPrimitive();
}
