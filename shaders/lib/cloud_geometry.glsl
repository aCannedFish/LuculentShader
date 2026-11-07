#ifndef LIB_CLOUD_GEOMETRY_GLSL
#define LIB_CLOUD_GEOMETRY_GLSL

// 球心在玩家水平位置下方 12000 格，纵向固定以保留世界云高。
// 云层沿径向拥有厚度；天气纹理仍锚定世界坐标，移动时不会跟随玩家平移。
const float CLOUD_SPHERE_RADIUS = 12000.0;
// 单位方向的 y 分量等于仰角的正弦，主视图和云环境缓存共用下限。
const float CLOUD_MIN_DIRECTION_Y = -sin(radians(6.0));

vec2 cloudAltitudeBounds() {
    return vec2(CLOUD_HEIGHT - CLOUD_THICKNESS * 0.65,
                CLOUD_HEIGHT + CLOUD_THICKNESS * 1.90);
}

// 有理化径向高度，避免在头顶附近用两个较大的浮点数直接相减。
float cloudRadialAltitude(vec3 world) {
    vec2 offset = world.xz - cameraPosition.xz;
    float vertical = world.y + CLOUD_SPHERE_RADIUS;
    float radius = length(vec3(offset, vertical));
    return world.y + dot(offset, offset) / max(radius + vertical, 1.0);
}

// 不再由地形视距裁剪云层；远端淡出仅保护有限的积分预算。
float cloudRenderDistance() {
    return CLOUD_DISTANCE;
}

// 仰角从 −6 度升到水平线时逐渐恢复覆盖和密度。
// 使用同一空间密度供主视图、反射与阴影采样，避免各路径出现不同云形。
float cloudHorizonVisibility(vec3 world) {
    vec3 offset = world - cameraPosition;
    float distance = length(offset);
    float elevation = offset.y / max(distance, 0.001);
    float angular = smoothstep(CLOUD_MIN_DIRECTION_Y, 0.0, elevation);
    float range = 1.0 - smoothstep(CLOUD_DISTANCE * 0.75, CLOUD_DISTANCE, distance);
    return angular * angular * range * range;
}

// 稳定求解射线与给定径向高度的球面交点，支持反射的偏移起点。
bool cloudSphereRoots(vec3 origin, vec3 ray, float altitude, out vec2 roots) {
    vec3 offset = vec3(origin.xz - cameraPosition.xz, origin.y + CLOUD_SPHERE_RADIUS);
    vec3 direction = ray.xzy;
    float along = dot(offset, direction);
    float boundary = dot(offset.xy, offset.xy)
                   + (origin.y - altitude) * (2.0 * CLOUD_SPHERE_RADIUS + origin.y + altitude);
    float discriminant = along * along - boundary;
    roots = vec2(0.0);
    if (discriminant <= 0.0) {
        return false;
    }
    float root = sqrt(discriminant);
    float q = -along - (along >= 0.0 ? root : -root);
    float other = boundary / q;
    roots = vec2(min(q, other), max(q, other));
    return true;
}

// 用场景深度截断球壳。掠过内球时可能依次遇到近、远两段云，
// 保留两段之间的积分范围，密度函数会跳过径向高度在云底以下的样本。
bool cloudRayInterval(vec3 origin, vec3 ray, float limit, out float entry, out float exit) {
    entry = 0.0;
    exit = 0.0;
#if SIMPLE_DIMENSION != 0
    return false;
#endif
    // 相机射线的仰角沿途恒定；偏移起点的反射和阴影按样本位置判断。
    if (ray.y <= CLOUD_MIN_DIRECTION_Y && all(equal(origin, cameraPosition))) {
        return false;
    }
    vec2 altitude = cloudAltitudeBounds();
    vec2 outer;
    if (!cloudSphereRoots(origin, ray, altitude.y, outer)) {
        return false;
    }
    entry = max(outer.x, 0.0);
    exit = min(outer.y, min(limit, CLOUD_DISTANCE));
    vec2 inner;
    if (cloudSphereRoots(origin, ray, altitude.x, inner)) {
        if (inner.x <= entry) {
            entry = max(entry, inner.y);
        } else if (inner.y >= exit) {
            exit = min(exit, inner.x);
        }
    }
    return exit > entry;
}

#endif
