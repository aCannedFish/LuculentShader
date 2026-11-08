/* Diffuse transport uses a conservative six-lobe angular stencil. Free-space
 * transport preserves energy, while material reflectance bounds feedback.
 * Direct sunlight, native skylight and independently occluded lamps seed only
 * exposed solid faces. The field therefore contains bounced light exclusively.
 */
/* RENDERTARGETS: 12 */
/* Six directional radiance lobes in a camera-relative voxel volume. A lobe
 * travels through air and reflects at the exposed face of an opaque voxel.
 * Separate faces prevent a lit exterior from illuminating a sealed interior.
 * Headers store the field's own origin, independent of the direct-light passes.
 */
#ifndef SIMPLE_CONVENTIONAL_GI_GLSL
#define SIMPLE_CONVENTIONAL_GI_GLSL
/* Compact local lighting. Fixed-size C5 is an image-only integer voxel store,
 * C10 holds three source identities, C11 their cached RGB transmission,
 * and C8 low-energy diffuse radiance. Direct RGB contributions remain separate
 * until the material consumer adds their independently shadowed radiance.
 */
#include "/lib/lighting/local_volume.glsl"

#if GI_QUALITY > 0
uniform sampler2D colortex12;

ivec3 giDirection(int face) {
    ivec3 direction = ivec3(0);
    direction[face / 2] = face % 2 == 0 ? 1 : -1;
    return direction;
}

ivec2 giAddress(ivec3 cell, int face) {
    return lpvAddress(cell) + ivec2(0, face * textureSize(colortex8, 0).y);
}

ivec3 giStoredOrigin() {
    int height = textureSize(colortex8, 0).y;
    vec3 high = texelFetch(colortex12, ivec2(1, 0), 0).xyz;
    vec3 middle = texelFetch(colortex12, ivec2(1, height), 0).xyz;
    vec3 low = texelFetch(colortex12, ivec2(1, height * 2), 0).xyz;
    return ivec3(round(high * 1048576.0 + middle * 1024.0 + low));
}

bool giHistoryValid() {
    vec4 header = texelFetch(colortex12, ivec2(0), 0);
    int delta = (frameCounter - lpvHeaderFrame(header) + 720720) % 720720;
    ivec3 origin = giStoredOrigin();
    return header.w == 1973.0 && int(round(header.x)) == lpvShape().x
        && delta <= 1 && all(lessThanEqual(abs(lpvOrigin(cameraPosition) - origin), ivec3(2)));
}

// Reads always use the stored origin, so substeps and integer camera movement
// share the same mapping. Newly uncovered cells receive no stale radiance.
vec3 giRead(ivec3 cell, int face, ivec3 shift) {
    ivec3 previous = cell + shift;
    if (!lpvInside(cell) || !lpvInside(previous)) return vec3(0.0);
    return max(texelFetch(colortex12, giAddress(previous, face), 0).rgb, vec3(0.0));
}

// The six-lobe quadrature integrates the normal-facing radiance. Sampling only
// air prevents interpolation with the bright opposite face of a one-block wall.
vec3 giSurfaceIrradiance(vec3 viewPosition, vec3 normalView) {
    if (GI_STRENGTH <= 0.0 || !giHistoryValid()) return vec3(0.0);
    vec3 normal = normalize(mat3(gbufferModelViewInverse) * normalView);
    vec3 relative = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 world = relative + cameraPosition + normal * 0.55;
    vec3 position = world - vec3(lpvOrigin(cameraPosition)) - 0.5;
    ivec3 first = ivec3(floor(position));
    vec3 fraction = fract(position);
    vec3 irradiance = vec3(0.0);
    float total = 0.0;
    for (int corner = 0; corner < 8; corner++) {
        ivec3 offset = ivec3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1);
        ivec3 cell = first + offset;
        if (!lpvInside(cell) || lpvOpaque(lpvVoxel(cell))) continue;
        vec3 blend = mix(1.0 - fraction, fraction, vec3(offset));
        float weight = blend.x * blend.y * blend.z;
        for (int axis = 0; axis < 3; axis++) {
            int face = axis * 2 + (normal[axis] > 0.0 ? 1 : 0);
            irradiance += texelFetch(colortex12, giAddress(cell, face), 0).rgb
                * abs(normal[axis]) * weight;
        }
        total += weight;
    }
    vec3 border = vec3(lpvShape()) * 0.5 - abs(relative + normal * 0.55);
    float coverage = smoothstep(1.0, 5.0, min(border.x, min(border.y, border.z)));
    return max(irradiance, vec3(0.0)) / max(total, 0.001) * GI_STRENGTH * coverage;
}
#endif
#endif

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_shadow.glsl"

/* 表面光照。分别计算日月直射、天空环境光与局部方块光；AO 作用于间接项。
 * 配套数据就绪时接入独立点光阴影和体素 GI，其他情况使用原版光照场。
 */
#include "/lib/lighting/lighting_transport.glsl"

layout(location=0) out vec4 result;

#if GI_QUALITY > 0
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

// Native sky levels constrain exposure, but a single block can have lit and
// unlit faces. Test the air column outside this face before injecting sky energy.
float giSkyVisibility(ivec3 air) {
    for (int stepIndex = 0; stepIndex < COLOURED_VOLUME_SIZE / 2; stepIndex++) {
        if (!lpvInside(air)) return 1.0;
        uint voxel = lpvVoxel(air);
        if (lpvOpaque(voxel)) return 0.0;
        air.y++;
    }
    return 0.0;
}

// A surface offset avoids its own depth without extending through neighbouring
// blocks. Outside the real shadow coverage no unverified sunlight is injected.
float giSunVisibility(vec3 world, vec3 normal) {
    vec4 clip = shadowProjection * shadowModelView
        * vec4(world + normal * 0.06 - cameraPosition, 1.0);
    vec3 uv = distortShadow(clip.xyz / clip.w) * 0.5 + 0.5;
    if (any(lessThan(uv, vec3(0.001))) || any(greaterThan(uv, vec3(0.999)))) return 0.0;
    float bias = 0.04 * abs(shadowProjection[2][2]);
    return step(uv.z - bias, texture(shadowtex0, uv.xy).r);
}

// Cached per-source transmission is evaluated in the air outside this face.
// Reuse it for diffuse injection without tracing every lamp at every GI substep.
vec3 giLampIrradiance(ivec3 air, vec3 normal, vec3 receiver) {
    if (!lpvInside(air) || !lpvHeaderValid(texelFetch(colortex8, ivec2(0), 0))) return vec3(0.0);
    ivec2 address = lpvAddress(air);
    vec3 identities = texelFetch(colortex10, address, 0).rgb;
    vec3 light = vec3(0.0);
    for (int entry = 0; entry < 3; entry++) {
        int identity = int(round(identities[entry])) - 1;
        if (identity < 0) continue;
        ivec3 source = lpvCell(identity);
        uint material = lpvVoxel(source);
        if (lpvKind(material) != LPV_EMITTER) continue;
        vec3 ray = vec3(source) + vec3(0.5, 0.72, 0.5) - receiver;
        float distance = length(ray);
        float cosine = max(dot(normal, ray / max(distance, 0.001)), 0.0);
        vec3 colour = lpvColour(material);
#if ENABLE_COLOURED_LIGHTING == 0
        colour = vec3(1.0, 0.65, 0.32);
#endif
        vec3 transmission = texelFetch(colortex11,
            address + ivec2(0, entry * textureSize(colortex8, 0).y), 0).rgb;
        light += colour * colour * lpvSourceEnergy(distance, lpvEmission(material))
            * transmission * cosine;
    }
    return light;
}
#endif

void main() {
    result = vec4(0.0);
#if GI_QUALITY > 0
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    int height = textureSize(colortex8, 0).y;
    int face = pixel.y / height;
    int index = pixel.x + (pixel.y % height) * textureSize(colortex8, 0).x;
    if (index < LPV_HEADER_SIZE) {
        vec3 origin = vec3(lpvOrigin(cameraPosition));
        vec3 part = face == 0 ? floor(origin / 1048576.0)
            : face == 1 ? mod(floor(origin / 1024.0), 1024.0) : mod(origin, 1024.0);
        result = index == 0
            ? vec4(lpvShape().x, frameCounter % 1024, frameCounter / 1024, 1973.0)
            : vec4(part, 1.0);
        return;
    }
    if (face >= 6 || index - LPV_HEADER_SIZE >= lpvShape().x * lpvShape().y * lpvShape().z) return;
    ivec3 cell = lpvCell(index - LPV_HEADER_SIZE);
    ivec3 direction = giDirection(face);
    bool valid = giHistoryValid();
    ivec3 shift = valid ? lpvOrigin(cameraPosition) - giStoredOrigin() : ivec3(0);
    uint material = lpvVoxel(cell);
    if (lpvOpaque(material)) {
        ivec3 air = cell + direction;
        if (!lpvInside(air) || lpvOpaque(lpvVoxel(air))) return;
        vec3 normal = vec3(direction);
        vec3 receiver = vec3(cell) + 0.5 + normal * 0.51;
        vec3 world = receiver + vec3(lpvOrigin(cameraPosition));
        vec3 direct = giLampIrradiance(air, normal, receiver);
#if SIMPLE_DIMENSION == 0
        vec3 sun = getSunLightColor() + getMoonLightColor();
        vec3 lightDirection = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
        float cosine = max(dot(normal, lightDirection), 0.0);
        if (cosine > 0.001) direct += sun * cosine * giSunVisibility(world, normal);
        float sky = lpvKind(material) == LPV_SOLID ? lpvEmission(material) / 15.0 : 0.0;
        direct += mix(vec3(0.48, 0.64, 1.0), vec3(0.8, 0.88, 1.0), getDayFactor())
            * sky * sky * giSkyVisibility(air) * (0.05 + 0.25 * getDayFactor()) * AMBIENT_STRENGTH
            * (0.35 + 0.65 * max(normal.y, 0.0));
#endif
        vec3 incoming = vec3(0.0);
#if GI_MULTIBOUNCE == 1
        if (valid) {
            incoming = giRead(air, face ^ 1, shift) * 0.6;
            for (int side = 0; side < 6; side++) {
                if (side / 2 != face / 2) incoming += giRead(air, side, shift) * 0.1;
            }
        }
#endif
        vec3 albedo = lpvKind(material) == LPV_SOLID ? lpvColour(material) : vec3(0.45);
        result.rgb = min(albedo, vec3(0.85)) * (direct + incoming * GI_REFLECTANCE);
    } else if (valid) {
        // A narrow cone spreads low-frequency radiance over the four adjacent
        // lobes. Weights sum to one; air cannot create or reflect energy.
        ivec3 upstream = cell - direction;
        vec3 incoming = giRead(upstream, face, shift) * 0.68;
        if (!lpvOpaque(lpvVoxel(upstream))) {
            for (int side = 0; side < 6; side++) {
                if (side / 2 != face / 2) incoming += giRead(upstream, side, shift) * 0.08;
            }
        } else {
            incoming = giRead(upstream, face, shift);
        }
        if (lpvKind(material) == LPV_GLASS) incoming *= lpvColour(material) * lpvColour(material);
        result.rgb = incoming * 0.985;
    }
    result.rgb = clamp(result.rgb, vec3(0.0), vec3(8.0));
    result.a = float(lpvKind(material));
#endif
}
