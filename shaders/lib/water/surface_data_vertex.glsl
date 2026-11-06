// Water for water vertex.
#ifndef LIB_WATER_GLSL
#define LIB_WATER_GLSL

/*
 * Companion-provided light positions, independent cube-face shadows and diffuse
 * radiance volumes. All data remains linear HDR. Missing companion data selects
 * the existing Minecraft light-field fallback through companionReady = 0.
 * Block-light energy and wall occlusion always come from the native light field;
 * the companion supplies emitter hue (hue volume) and point-light visibility.
 */
#include "/lib/lighting/companion_lighting_water_vertex.glsl"

// block.properties 将水映射到此 ID，避免玻璃也产生波浪。
const float WATER_BLOCK_ID = 100.0;
const float WATER_IOR = 1.333;
uniform sampler2D colortex13;

// 无偏振介质 Fresnel。eta 是入射侧/透射侧折射率，临界角外返回全反射。
float waterDielectricFresnel(float cosine, float eta) {
    float c = clamp(cosine, 0.0, 1.0);
    float discriminant = 1.0 - eta * eta * (1.0 - c * c);
    if (discriminant <= 0.0) {
        return 1.0;
    }
    float transmitted = sqrt(discriminant);
    float parallel = (eta * c - transmitted) / max(eta * c + transmitted, EPSILON);
    float perpendicular = (c - eta * transmitted) / max(c + eta * transmitted, EPSILON);
    return clamp((parallel * parallel + perpendicular * perpendicular) * 0.5, 0.0, 1.0);
}

// 重载、离水、传送及缺帧时拒绝历史；竖直移动按相机位移预测真实水深。
bool validWaterMediumHistory(vec4 history) {
    float previousFrame = mod(float(frameCounter) + 720719.0, 720720.0);
    return abs(history.w - 4183.0) < 0.5 && abs(history.z - previousFrame) < 0.5
        && length(cameraPosition - previousCameraPosition) < 16.0;
}

// 水面几何与参数各自以 alpha=1 标记有效片元，玻璃以 alpha=0 保留这些数据。
// 返回既有逻辑使用的布局：八面体法线 RG、天空可见度 B、线性视图深度 A。
vec4 readWaterSurface(sampler2D geometry, sampler2D parameters, vec2 uv) {
    vec4 surface = texture(geometry, uv);
    if (surface.a < 0.5) {
        return vec4(0.0);
    }
    float sky = texture(parameters, uv).r;
    return vec4(surface.rg, sky, surface.b);
}

vec3 readWaterScattering(sampler2D geometry, sampler2D scattering, vec2 uv) {
    return texture(scattering, uv).rgb;
}

// 从透明水面附件的线性深度恢复位置，供水面合成与水深估计共用。
vec3 waterSurfacePosition(vec2 uv, float linearDepth) {
    vec4 ray = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    return ray.xyz * (linearDepth / max(-ray.z, EPSILON));
}

// 空气到水的折射率约为 1.333，法向入射的反射率约为 2%。
float waterFresnel(float cosine) {
    return 0.0204 + 0.9796 * pow(1.0 - clamp(cosine, 0.0, 1.0), 5.0);
}

// 八面体编码保留完整法线方向，包括负 Z；两个通道足以用于反射。
vec2 waterSign(vec2 value) {
    return vec2(value.x >= 0.0 ? 1.0 : -1.0, value.y >= 0.0 ? 1.0 : -1.0);
}

vec2 encodeWaterNormal(vec3 normal) {
    normal /= abs(normal.x) + abs(normal.y) + abs(normal.z);
    vec2 encoded = normal.xy;
    if (normal.z < 0.0) {
        encoded = (1.0 - abs(encoded.yx)) * waterSign(encoded);
    }
    return encoded * 0.5 + 0.5;
}

vec3 decodeWaterNormal(vec2 encoded) {
    vec2 value = encoded * 2.0 - 1.0;
    vec3 normal = vec3(value, 1.0 - abs(value.x) - abs(value.y));
    if (normal.z < 0.0) {
        normal.xy = (1.0 - abs(normal.yx)) * waterSign(normal.xy);
    }
    return normalize(normal);
}

// 优先读取原生水柱深度与水面天光，避免深水亮度随相机朝向变化。
// 缺少新元数据时退回屏幕探针，仍只接受水平水面并平均水深。
vec2 estimateWaterMedium(sampler2D surfaces, sampler2D parameters) {
    if (hasCompanionLighting()) {
        vec4 medium = texture(companionAtlas, vec2(0.5, 7.5) / companionAtlasSize());
        if (abs(medium.w - 1573.0) < 0.5 && medium.z > 0.5) {
            return medium.xy;
        }
    }
    float depthSum = 0.0;
    float count = 0.0;
    for (int x = 0; x < 3; x++) {
        for (int y = 0; y < 3; y++) {
            vec2 uv = vec2(0.15 + float(x) * 0.35, 0.60 + float(y) * 0.18);
            vec4 surface = readWaterSurface(surfaces, parameters, uv);
            if (surface.a > 0.001) {
                vec3 normal = mat3(gbufferModelViewInverse) * decodeWaterNormal(surface.xy);
                vec3 relative = (gbufferModelViewInverse
                    * vec4(waterSurfacePosition(uv, surface.a), 1.0)).xyz;
                float weight = smoothstep(0.02, 0.25, relative.y)
                    * smoothstep(0.65, 0.90, abs(normal.y));
                depthSum += max(relative.y, 0.0) * weight;
                count += weight;
            }
        }
    }
    float skylight = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
    vec4 history = texture(colortex13, vec2(0.5));
    bool valid = validWaterMediumHistory(history);
    float predicted = valid ? max(history.x + previousCameraPosition.y - cameraPosition.y, 0.0)
        : (1.0 - skylight) * 15.0;
    // 水面退出视野时沿用水位预测，不在“屏幕探针/天光估计”之间跳换。
    float observed = count > 0.001 ? depthSum / count : predicted;
    float depth = mix(predicted, observed, valid ? 1.0 - exp(-min(frameTime, 0.1) * 6.0) : 1.0);
    // 屏幕上某一块水面的天光不再决定整帧雾色，遮挡过渡只跟随相机天光。
    float sky = valid ? mix(history.y, skylight, 1.0 - exp(-min(frameTime, 0.1) * 3.5)) : skylight;
    return vec2(clamp(depth, 0.0, 64.0), sky);
}

#include "/lib/water_waves.glsl"

#endif  // LIB_WATER_GLSL
