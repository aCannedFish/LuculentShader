// 薄水膜复用水面的屏幕反射查询。输入为手部之前的世界颜色与匹配深度。
// 未命中的方向使用现有天空/云环境，不把清除色混成黑色反射。
#ifndef LIB_PUDDLE_REFLECTION_GLSL
#define LIB_PUDDLE_REFLECTION_GLSL
#include "/lib/reflections/bsl_water_reflection.glsl"

vec3 puddleMirrorRadiance(sampler2D scene, sampler2D depths, vec3 position, vec3 normal) {
    vec3 reflected = reflect(normalize(position), normal);
    vec3 world = normalize(mat3(gbufferModelViewInverse) * reflected);
    vec4 cloud = cloudEnvironment(world);
    vec3 background = cloud.rgb + skyRadiance(world) * (1.0 - cloud.a);
    vec4 traced = traceBslWaterReflection(scene, depths, position + normal * 0.025, normal);
    return mix(background, traced.rgb, clamp(traced.a, 0.0, 1.0));
}
#endif
