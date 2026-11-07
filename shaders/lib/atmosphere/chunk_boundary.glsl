// 与主视图共用天空和云环境，主画面及水体场景源只各自融合一次。
#ifndef LIB_CHUNK_BOUNDARY_GLSL
#define LIB_CHUNK_BOUNDARY_GLSL
#include "/lib/post/chunk_transition.glsl"

vec4 chunkBoundaryOverlay(vec3 direction, float horizontalDistance) {
    float fade = chunkBoundaryFade(horizontalDistance);
    if (isEyeInWater != 0 || fade <= 0.0) {
        return vec4(0.0);
    }
    vec4 cloud = cloudEnvironment(direction);
    vec3 background = cloud.rgb + skyRadiance(direction) * (1.0 - cloud.a);
    return vec4(background * fade, fade);
}
#endif
