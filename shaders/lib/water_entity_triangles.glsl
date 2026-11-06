#ifndef LUCULENT_WATER_ENTITY_TRIANGLES
#define LUCULENT_WATER_ENTITY_TRIANGLES
#include "/lib/water_environment_layout.glsl"

// Shadow pixels refer to actual submitted actor triangles. Entity UVs do not
// belong to the block atlas, so their unused UV-X field carries this index.
// Only geometry is stored here; alpha-tested radiance stays in the shadow map.
const int waterEntityCapacity = 4096;
const int waterEntityWords = waterEntityCapacity * 9;

ivec2 waterEntityAddress(int triangle, int word) {
    return waterStorageAddress(-waterEnvironmentWords - waterEntityWords + triangle * 9 + word);
}

vec3 waterEntityVertex(int triangle, int vertex) {
    int offset = vertex * 3;
    return uintBitsToFloat(uvec3(
        imageLoad(colorimg5, waterEntityAddress(triangle, offset)).r,
        imageLoad(colorimg5, waterEntityAddress(triangle, offset + 1)).r,
        imageLoad(colorimg5, waterEntityAddress(triangle, offset + 2)).r));
}

bool waterEntityReady(int triangle) {
    int row = imageSize(colorimg5).y - 1;
    return triangle >= 0 && triangle < waterEntityCapacity
        && imageLoad(colorimg5, ivec2(28, row)).r == uint(frameCounter) + 1u
        && uint(triangle) < imageLoad(colorimg5, ivec2(29, row)).r;
}

// Coordinates use the camera's integer origin, preserving subpixel movement.
// Moller-Trumbore accepts the submitted winding from either visible side.
bool waterEntityIntersection(int triangle, vec3 origin, vec3 ray, out float distance) {
    distance = -1.0;
    if (!waterEntityReady(triangle)) return false;
    vec3 a = waterEntityVertex(triangle, 0);
    vec3 e1 = waterEntityVertex(triangle, 1) - a;
    vec3 e2 = waterEntityVertex(triangle, 2) - a;
    vec3 p = cross(ray, e2);
    float determinant = dot(e1, p);
    if (abs(determinant) < 1e-10) return false;
    vec3 relative = origin + fract(cameraPosition) - a;
    vec3 q = cross(relative, e1);
    vec2 barycentric = vec2(dot(relative, p), dot(ray, q)) / determinant;
    if (any(lessThan(barycentric, vec2(-0.0001)))
        || barycentric.x + barycentric.y > 1.0001) return false;
    distance = dot(e2, q) / determinant;
    return distance > 0.0001;
}

// Validate a second-view material sample against the finite primitive. A
// nearby depth alone cannot license extending an actor's face across the lake.
bool waterEntityContains(int triangle, vec3 point) {
    if (!waterEntityReady(triangle)) return false;
    vec3 a = waterEntityVertex(triangle, 0);
    vec3 e1 = waterEntityVertex(triangle, 1) - a;
    vec3 e2 = waterEntityVertex(triangle, 2) - a;
    vec3 relative = point + fract(cameraPosition) - a;
    vec3 normal = cross(e1, e2);
    float area = length(normal);
    if (area < 1e-10 || abs(dot(relative, normal)) > area * 0.004) return false;
    float aa = dot(e1, e1);
    float ab = dot(e1, e2);
    float bb = dot(e2, e2);
    float denominator = aa * bb - ab * ab;
    if (denominator <= 1e-18) return false;
    vec2 projection = vec2(dot(relative, e1), dot(relative, e2));
    vec2 barycentric = vec2(bb * projection.x - ab * projection.y,
                            aa * projection.y - ab * projection.x) / denominator;
    return all(greaterThanEqual(barycentric, vec2(-0.0001)))
        && barycentric.x + barycentric.y <= 1.0001;
}
#endif
