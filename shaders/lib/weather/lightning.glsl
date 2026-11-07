// 真实闪电事件的照明与短余辉。原生顶点提交触发脉冲，Iris 另提供精确位置。
// 只读取加载器状态和自己的上一帧记录，不生成随机闪电或外部场景数据。
#ifndef LIB_LIGHTNING_GLSL
#define LIB_LIGHTNING_GLSL
const int LIGHTNING_ENTITY_ID = (104);

// 原生电弧顶点触发同帧脉冲。位置量化只用于柔和云照明，原生几何不变。
void recordLightningGeometry(vec3 relative) {
#if ENABLE_LIGHTNING == 1 && SIMPLE_DIMENSION == 0
    int row = imageSize(colorimg5).y - 1;
    uint stamp = uint(frameCounter) + 1u;
    if (imageLoad(colorimg5, ivec2(31, row)).r == stamp) {
        return;
    }
    if (imageAtomicExchange(colorimg5, ivec2(31, row), stamp) != stamp) {
        uvec3 cell = uvec3(clamp(floor(relative * 0.25 + 512.0), 0.0, 1023.0));
        uint position = cell.x | (cell.y << 10u) | (cell.z << 20u);
        imageStore(colorimg5, ivec2(30, row), uvec4(position));
    }
#endif
}

// 校验上一帧记录，并结合原生事件和顶点脉冲得到世界位置与衰减强度。
vec4 lightningState() {
#if ENABLE_LIGHTNING == 0 || SIMPLE_DIMENSION != 0
    return vec4(0.0);
#else
    int row = imageSize(colorimg5).y - 1;
    bool rendered = imageLoad(colorimg5, ivec2(31, row)).r == uint(frameCounter) + 1u;
    float livePulse = max(lightningFlash, rendered ? 1.0 : 0.0);
    vec4 previous = vec4(0.0);
    bool previousGeometry = false;
    if (frameCounter > 0) {
        vec4 header = texelFetch(colortex13, ivec2(2, 0), 0);
        float previousFrame = mod(float(frameCounter) + 720719.0, 720720.0);
        if (abs(header.x - previousFrame) < 0.5
            && abs(header.w - POST_HISTORY_SIGNATURE) < 0.5
            && all(lessThan(abs(header.yz - vec2(viewWidth, viewHeight)), vec2(0.5)))
            && length(cameraPosition - previousCameraPosition) < 32.0) {
            previous = texelFetch(colortex13, ivec2(4, 0), 0);
            previousGeometry = texelFetch(colortex13, ivec2(3, 0), 0).w >= 2.0;
            if (any(isnan(previous)) || any(isinf(previous)) || previous.w > 1.001) {
                previous = vec4(0.0);
            }
            previous.w *= exp(-max(frameTime, 0.0) * 18.0);
        }
    }
#ifdef IS_IRIS
    if (lightningBoltPosition.w > 0.5) {
        vec3 world = cameraPosition + lightningBoltPosition.xyz;
        bool trackedGeometry = rendered || (previousGeometry && distance(previous.xyz, world) < 4.0);
        float pulse = trackedGeometry ? max(rendered ? 1.0 : 0.0, previous.w) : 1.0;
        return vec4(world, pulse);
    }
#endif
    if (rendered) {
        uint positionBits = imageLoad(colorimg5, ivec2(30, row)).r;
        vec3 cell = vec3(positionBits & 1023u, (positionBits >> 10u) & 1023u, (positionBits >> 20u) & 1023u);
        return vec4(cameraPosition + (cell + 0.5 - 512.0) * 4.0, max(livePulse, previous.w));
    }
    return previous.w > 0.001 ? previous : vec4(0.0);
#endif
}

// 用户亮度只作用于照明输出，不改变缓存中的归一化事件强度。
float lightningPulse(vec4 source) {
#if ENABLE_LIGHTNING == 0 || SIMPLE_DIMENSION != 0
    return 0.0;
#else
#ifdef IS_IRIS
    if (lightningBoltPosition.w > 0.5 || source.w > 0.001) {
        return clamp(source.w, 0.0, 1.0) * LIGHTNING_STRENGTH;
    }
#endif
    return clamp(max(lightningFlash, source.w), 0.0, 1.0) * LIGHTNING_STRENGTH;
#endif
}

// 近处一旦有原生电弧提交，保持该事件的几何节奏；远雷仍能照亮云体。
bool lightningGeometrySeen() {
#if ENABLE_LIGHTNING == 0 || SIMPLE_DIMENSION != 0
    return false;
#else
    int row = imageSize(colorimg5).y - 1;
    if (imageLoad(colorimg5, ivec2(31, row)).r == uint(frameCounter) + 1u) {
        return true;
    }
#ifdef IS_IRIS
    if (lightningBoltPosition.w > 0.5 && frameCounter > 0) {
        vec4 header = texelFetch(colortex13, ivec2(2, 0), 0);
        vec4 source = texelFetch(colortex13, ivec2(4, 0), 0);
        float previousFrame = mod(float(frameCounter) + 720719.0, 720720.0);
        return abs(header.w - POST_HISTORY_SIGNATURE) < 0.5
            && abs(header.x - previousFrame) < 0.5
            && texelFetch(colortex13, ivec2(3, 0), 0).w >= 2.0
            && distance(source.xyz, cameraPosition + lightningBoltPosition.xyz) < 4.0;
    }
#endif
    return false;
#endif
}

// 放电柱在实际闪电位置的上方照亮云体，距离衰减形成明亮核心与柔和外缘。
vec3 lightningCloudIrradiance(vec3 world, vec4 source, float pulse) {
    if (pulse <= 0.001) {
        return vec3(0.0);
    }
    float influence = 0.06;
    if (source.w > 0.001) {
        vec2 offset = world.xz - source.xz;
        float radial = 1.0 / (1.0 + dot(offset, offset) / 14400.0);
        float vertical = exp(-max(abs(world.y - source.y - 160.0) - 120.0, 0.0) / 240.0);
        influence = radial * radial * vertical;
    }
    return vec3(3.2, 4.4, 7.0) * pulse * influence;
}

// 薄雾散射与云内电光共用事件和位置，限制近地面增益以保留雷雨暗部。
vec3 lightningFogIrradiance(vec3 world, vec4 source, float pulse) {
    return lightningCloudIrradiance(world, source, pulse) * 0.10;
}

// 保留原生折线几何与透明度，在线性 HDR 中给电弧足够的核心亮度。
vec3 lightningCoreRadiance(vec3 vertexColor) {
#if ENABLE_LIGHTNING == 1 && SIMPLE_DIMENSION == 0
    return vertexColor * vec3(48.0, 58.0, 80.0) * LIGHTNING_STRENGTH;
#else
    return vertexColor;
#endif
}
#endif
