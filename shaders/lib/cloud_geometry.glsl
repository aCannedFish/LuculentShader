#ifndef LIB_CLOUD_GEOMETRY_GLSL
#define LIB_CLOUD_GEOMETRY_GLSL

// 球心在玩家水平位置下方 12000 格，纵向固定以保留世界云高。
// 云层沿径向拥有厚度；天气纹理仍锚定世界坐标，移动时不会跟随玩家平移。
const float CLOUD_SPHERE_RADIUS = 12000.0;

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

// 仰角 0 到约 12 度逐渐恢复覆盖和密度，地平线以下不生成云。
// 使用同一空间密度供主视图、反射与阴影采样，避免各路径出现不同云形。
float cloudHorizonVisibility(vec3 world) {
    vec3 offset = world - cameraPosition;
    float distance = length(offset);
    float elevation = offset.y / max(distance, 0.001);
    float angular = smoothstep(0.0, 0.208, elevation);
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

// 取前方第一个球壳区间，再与玩家的上半空间和场景深度相交。
// 内球内部从其远交点进入云层；外部射线在近交点处离开当前云段。
bool cloudRayInterval(vec3 origin, vec3 ray, float limit, out float entry, out float exit) {
    entry = 0.0;
    exit = 0.0;
#if SIMPLE_DIMENSION != 0
    return false;
#endif
    vec2 altitude = cloudAltitudeBounds();
    vec2 outer;
    if (!cloudSphereRoots(origin, ray, altitude.y, outer)) {
        return false;
    }
    entry = max(outer.x, 0.0);
    exit = min(outer.y, min(limit, CLOUD_DISTANCE));
    vec2 inner;
    if (cloudSphereRoots(origin, ray, altitude.x, inner)) {
        if (inner.x > entry) {
            exit = min(exit, inner.x);
        } else if (inner.y > entry) {
            entry = inner.y;
        }
    }
    if (abs(ray.y) > 0.000001) {
        float horizon = (cameraPosition.y - origin.y) / ray.y;
        if (ray.y > 0.0) {
            entry = max(entry, horizon);
        } else {
            exit = min(exit, horizon);
        }
    } else if (origin.y <= cameraPosition.y) {
        return false;
    }
    return exit > entry;
}

#endif
