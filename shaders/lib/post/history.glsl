// C13 首五个纹素保存相机及闪电状态，其余保存 HDR 与线性深度。
#ifndef LIB_POST_HISTORY_GLSL
#define LIB_POST_HISTORY_GLSL

#include "/lib/post/history_layout.glsl"

bool postCameraHistoryValid(sampler2D history) {
    vec4 state = texelFetch(history, ivec2(1, 0), 0);
    vec2 size = texelFetch(history, ivec2(2, 0), 0).yz;
    return frameCounter > 0 && !any(isnan(state)) && !any(isinf(state))
        && state.x > 0.0 && state.y > 0.0
        && abs(state.w - POST_CAMERA_SIGNATURE) < 0.5
        && all(lessThan(abs(size - vec2(viewWidth, viewHeight)), vec2(0.5)));
}

bool postReservedPixel(ivec2 pixel) {
    return pixel.y == 0 && pixel.x < POST_METADATA_PIXELS;
}

// 分辨率、视场角、缺帧、传送和进出介质后重新收敛，避免沿用旧场景。
bool postHistoryValid(sampler2D history) {
    if (frameCounter < 1) {
        return false;
    }
    vec4 state = texelFetch(history, ivec2(2, 0), 0);
    vec4 projection = texelFetch(history, ivec2(3, 0), 0);
    float previousFrame = mod(float(frameCounter) + 720719.0, 720720.0);
    vec2 scale = vec2(postRawProjection()[0][0], postRawProjection()[1][1]);
    return abs(state.x - previousFrame) < 0.5
        && all(lessThan(abs(state.yz - vec2(viewWidth, viewHeight)), vec2(0.5)))
        && abs(state.w - POST_HISTORY_SIGNATURE) < 0.5
        && all(lessThan(abs(projection.xy - scale), max(abs(scale) * 0.02, vec2(0.001))))
        && abs(projection.z - float(isEyeInWater)) < 0.5
        && length(cameraPosition - previousCameraPosition) < 8.0
        && dot(gbufferModelViewInverse[2].xyz, vec3(gbufferPreviousModelView[0].z,
            gbufferPreviousModelView[1].z, gbufferPreviousModelView[2].z)) > 0.5
        && frameTime < 0.5;
}

float postLinearDepth(float depth) {
    vec4 point = postRawProjectionInverse() * vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
    return max(-point.z / point.w, 0.0);
}

bool postHandPixel(sampler2D depths, sampler2D worldDepths, vec2 uv) {
    float depth = textureLod(depths, uv, 0.0).r;
    float world = textureLod(worldDepths, uv, 0.0).r;
    return depth < 0.56 && world > depth + 0.00001;
}

// 使用未抖动投影计算运动，静止镜头不会把 TAA 子像素偏移当成运动。
vec3 postPreviousPosition(vec2 uv, float depth) {
    vec4 view = postRawProjectionInverse() * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    view /= view.w;
    vec4 previous;
    if (depth >= 0.999999) {
        vec3 direction = mat3(gbufferModelViewInverse) * view.xyz;
        previous = gbufferPreviousProjection
            * vec4(mat3(gbufferPreviousModelView) * direction, 0.0);
    } else {
        vec4 world = gbufferModelViewInverse * view;
        world.xyz += cameraPosition - previousCameraPosition;
        previous = gbufferPreviousProjection * gbufferPreviousModelView * world;
    }
    if (previous.w <= 0.00001) {
        return vec3(-1.0);
    }
    return vec3(previous.xy / previous.w * 0.5 + 0.5, previous.w);
}
#endif
