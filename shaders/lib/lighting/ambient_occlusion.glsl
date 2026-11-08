// Deterministic screen-space ambient obscurance, evaluated before transparency.
// Opaque depth excludes the first-person layer and does not include water yet.
#ifndef LIB_AMBIENT_OCCLUSION_GLSL
#define LIB_AMBIENT_OCCLUSION_GLSL
#if SSAO_QUALITY > 0
uniform sampler2D colortex4;

// Attenuate the captured indirect term without changing direct light or emission.
vec3 applyAmbientOcclusion(vec3 color, vec3 indirect, float visibility) {
    return max(color - indirect * (1.0 - visibility), vec3(0.0));
}

// Reconstruct from the actual pixel centre, including at viewport boundaries.
vec3 aoViewPosition(ivec2 pixel) {
    ivec2 size = textureSize(depthtex2, 0);
    pixel = clamp(pixel, ivec2(0), size - 1);
    float depth = texelFetch(depthtex2, pixel, 0).r;
    return screenToView((vec2(pixel) + 0.5) / vec2(size), min(depth, 0.999999));
}

// Ignore zero differences introduced by the viewport clamp.
vec3 aoNearestDifference(vec3 first, vec3 second) {
    if (dot(first, first) < 1e-20) {
        return second;
    }
    if (dot(second, second) < 1e-20) {
        return first;
    }
    return abs(first.z) < abs(second.z) ? first : second;
}

// The nearer difference avoids fitting a false plane across a silhouette.
// This uses pre-hand geometry even when the normal buffer contains the hand.
vec3 aoGeometricNormal(ivec2 pixel, vec3 position) {
    vec3 left = position - aoViewPosition(pixel + ivec2(-1, 0));
    vec3 right = aoViewPosition(pixel + ivec2(1, 0)) - position;
    vec3 down = position - aoViewPosition(pixel + ivec2(0, -1));
    vec3 up = aoViewPosition(pixel + ivec2(0, 1)) - position;
    ivec2 last = textureSize(depthtex2, 0) - 1;
    vec3 dx = pixel.x == 0 ? right : pixel.x == last.x ? left : aoNearestDifference(left, right);
    vec3 dy = pixel.y == 0 ? up : pixel.y == last.y ? down : aoNearestDifference(down, up);
    vec3 normal = cross(dx, dy);
    // Pixel-scale triangle areas can be tiny close to the camera. A general
    // vector epsilon would replace valid planes with the camera direction.
    float area = dot(normal, normal);
    normal = area > 1e-25 ? normal * inversesqrt(area)
        : safeNormalize(-position, vec3(0.0, 0.0, 1.0));
    return dot(normal, -position) < 0.0 ? -normal : normal;
}

// A world-space radius with a bounded screen footprint keeps nearby contacts
// detailed. Distant, subpixel and out-of-view samples fade without clamped taps.
float screenAmbientVisibility(vec2 uv, float depth) {
#if SSAO_QUALITY == 1
    const int samples = 8;
    const float maximumDistance = 48.0;
#else
    const int samples = 12;
    const float maximumDistance = 80.0;
#endif
    vec2 size = vec2(textureSize(depthtex2, 0));
    ivec2 center = ivec2(uv * size);
    vec2 centerUv = (vec2(center) + 0.5) / size;
    vec3 position = screenToView(centerUv, depth);
    float distance = -position.z;
    if (distance >= maximumDistance || distance <= 0.0 || SSAO_STRENGTH <= 0.0) {
        return 1.0;
    }
    vec2 projectedRadius = abs(vec2(gbufferProjection[0][0], gbufferProjection[1][1]))
        * (0.5 * 1.25 / max(distance, 0.05));
    float pixels = max(projectedRadius.x * size.x, projectedRadius.y * size.y);
    float footprint = min(1.0, 48.0 / max(pixels, 0.001));
    float radius = 1.25 * footprint;
    projectedRadius *= footprint;
    float fade = smoothstep(1.0, 2.0, pixels)
        * (1.0 - smoothstep(maximumDistance * 0.75, maximumDistance, distance));
    if (fade <= 0.0) {
        return 1.0;
    }
    vec3 normal = aoGeometricNormal(center, position);
    float sum = 0.0;
    for (int i = 0; i < samples; ++i) {
        float angle = float(i) * 2.39996323;
        float ring = sqrt((float(i) + 0.5) / float(samples));
        vec2 sampleUv = centerUv + vec2(cos(angle), sin(angle)) * ring * projectedRadius;
        if (any(lessThan(sampleUv, vec2(0.0))) || any(greaterThanEqual(sampleUv, vec2(1.0)))) {
            continue;
        }
        ivec2 pixel = ivec2(sampleUv * size);
        float sampleDepth = texelFetch(depthtex2, pixel, 0).r;
        if (sampleDepth >= 0.999999) {
            continue;
        }
        vec3 samplePosition = screenToView((vec2(pixel) + 0.5) / size, sampleDepth);
        vec3 offset = samplePosition - position;
        float squared = dot(offset, offset);
        float falloff = max(1.0 - squared / (radius * radius), 0.0);
        float horizon = max(dot(normal, offset) - radius * 0.02, 0.0)
            * inversesqrt(max(squared, 0.000001));
        sum += horizon * falloff * falloff;
    }
    float obscurance = min(sum * (3.0 / float(samples)) * SSAO_STRENGTH, 0.85);
    return 1.0 - obscurance * fade;
}
#endif
#endif
