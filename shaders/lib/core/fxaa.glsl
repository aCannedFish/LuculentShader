// Display-space edge reconstruction. Fast mode uses a short directional filter;
// quality mode finds edge endpoints and shifts the sample across that edge.
// Flat regions retain their centre sample. Dithering and HUD rendering follow AA.
vec3 displaySample(sampler2D scene, vec2 uv, vec2 pixel) {
    vec2 validUv = clamp(uv, pixel * 0.5, vec2(1.0) - pixel * 0.5);
    return textureLod(scene, validUv, 0.0).rgb;
}

float displayLuma(vec3 colour) {
#if AA_MODE == 1
    return dot(colour, vec3(0.299, 0.587, 0.114));
#else
    return dot(colour, vec3(0.2126, 0.7152, 0.0722));
#endif
}

vec3 filterDisplayEdges(sampler2D scene, vec2 uv) {
    vec2 pixel = 1.0 / vec2(textureSize(scene, 0));
    vec3 centre = displaySample(scene, uv, pixel);
#if AA_MODE == 0 || DEBUG_VIEW != 0
    return centre;
#elif AA_MODE == 3
    // TAA 后的轻度锐化；限制在相邻颜色范围，避免亮边与暗边。
    vec3 north = displaySample(scene, uv + vec2(0.0, pixel.y), pixel);
    vec3 south = displaySample(scene, uv - vec2(0.0, pixel.y), pixel);
    vec3 east = displaySample(scene, uv + vec2(pixel.x, 0.0), pixel);
    vec3 west = displaySample(scene, uv - vec2(pixel.x, 0.0), pixel);
    vec3 low = min(centre, min(min(north, south), min(east, west)));
    vec3 high = max(centre, max(max(north, south), max(east, west)));
    vec3 sharpened = centre + (centre - (north + south + east + west) * 0.25) * TAA_SHARPNESS;
    return clamp(sharpened, low, high);
#else
    float middle = displayLuma(centre);
    float nw = displayLuma(displaySample(scene, uv + pixel * vec2(-1.0, 1.0), pixel));
    float ne = displayLuma(displaySample(scene, uv + pixel * vec2(1.0, 1.0), pixel));
    float sw = displayLuma(displaySample(scene, uv + pixel * vec2(-1.0, -1.0), pixel));
    float se = displayLuma(displaySample(scene, uv + pixel * vec2(1.0, -1.0), pixel));
    float low = min(middle, min(min(nw, ne), min(sw, se)));
    float high = max(middle, max(max(nw, ne), max(sw, se)));
#if AA_MODE == 1
    // Match BSL v7.0p1's relative threshold, including dark water edges.
    if (high - low <= high * 0.0625) {
        return centre;
    }
    vec2 direction = vec2(nw + ne - sw - se, nw + sw - ne - se);
    float regularizer = max((nw + ne + sw + se) * 0.0625, 0.0078125);
    direction /= min(abs(direction.x), abs(direction.y)) + regularizer;
    direction = clamp(direction, vec2(-4.0), vec2(4.0)) * pixel;
    vec3 inner = 0.5 * (displaySample(scene, uv - direction / 6.0, pixel)
        + displaySample(scene, uv + direction / 6.0, pixel));
    vec3 outer = inner * 0.5 + 0.25 * (displaySample(scene, uv - direction * 0.5, pixel)
        + displaySample(scene, uv + direction * 0.5, pixel));
    float candidate = displayLuma(outer);
    return candidate < low || candidate > high ? inner : outer;
#else
    float north = displayLuma(displaySample(scene, uv + vec2(0.0, pixel.y), pixel));
    float south = displayLuma(displaySample(scene, uv - vec2(0.0, pixel.y), pixel));
    float west = displayLuma(displaySample(scene, uv - vec2(pixel.x, 0.0), pixel));
    float east = displayLuma(displaySample(scene, uv + vec2(pixel.x, 0.0), pixel));
    low = min(low, min(min(north, south), min(west, east)));
    high = max(high, max(max(north, south), max(west, east)));
    float contrast = high - low;
    if (contrast < max(0.03125, high * 0.125)) {
        return centre;
    }

    // Second differences distinguish the edge direction from texture gradient.
    float horizontal = abs(nw + sw - 2.0 * west)
        + 2.0 * abs(north + south - 2.0 * middle) + abs(ne + se - 2.0 * east);
    float vertical = abs(nw + ne - 2.0 * north)
        + 2.0 * abs(west + east - 2.0 * middle) + abs(sw + se - 2.0 * south);
    bool isHorizontal = horizontal >= vertical;
    float positive = isHorizontal ? north : east;
    float negative = isHorizontal ? south : west;
    bool usePositive = abs(positive - middle) >= abs(negative - middle);
    float adjacent = usePositive ? positive : negative;
    float edgeLuma = 0.5 * (middle + adjacent);
    float stopThreshold = 0.25 * abs(adjacent - middle);
    vec2 across = isHorizontal ? vec2(0.0, pixel.y) : vec2(pixel.x, 0.0);
    across *= usePositive ? 1.0 : -1.0;
    vec2 along = isHorizontal ? vec2(pixel.x, 0.0) : vec2(0.0, pixel.y);
    vec2 edge = uv + across * 0.5;
    vec2 endPositive = edge + along;
    vec2 endNegative = edge - along;
    float positiveDelta = displayLuma(displaySample(scene, endPositive, pixel)) - edgeLuma;
    float negativeDelta = displayLuma(displaySample(scene, endNegative, pixel)) - edgeLuma;
    bool positiveDone = abs(positiveDelta) >= stopThreshold;
    bool negativeDone = abs(negativeDelta) >= stopThreshold;
    const float steps[7] = float[7](1.0, 1.5, 2.0, 2.0, 4.0, 4.0, 8.0);
    for (int i = 0; i < 7; i++) {
        if (positiveDone && negativeDone) {
            break;
        }
        if (!positiveDone) {
            endPositive += along * steps[i];
            positiveDelta = displayLuma(displaySample(scene, endPositive, pixel)) - edgeLuma;
            positiveDone = abs(positiveDelta) >= stopThreshold;
        }
        if (!negativeDone) {
            endNegative -= along * steps[i];
            negativeDelta = displayLuma(displaySample(scene, endNegative, pixel)) - edgeLuma;
            negativeDone = abs(negativeDelta) >= stopThreshold;
        }
    }
    float positiveDistance = isHorizontal ? endPositive.x - uv.x : endPositive.y - uv.y;
    float negativeDistance = isHorizontal ? uv.x - endNegative.x : uv.y - endNegative.y;
    bool nearerPositive = positiveDistance < negativeDistance;
    float nearerDelta = nearerPositive ? positiveDelta : negativeDelta;
    float shift = 0.5 - min(positiveDistance, negativeDistance)
        / max(positiveDistance + negativeDistance, 1e-8);
    if ((nearerDelta < 0.0) == (middle < edgeLuma)) {
        shift = 0.0;
    }

    // Limit subpixel reconstruction to half a pixel to retain material detail.
    float average = (2.0 * (north + south + east + west) + nw + ne + sw + se) / 12.0;
    float subpixel = clamp(abs(average - middle) / contrast, 0.0, 1.0);
    subpixel = subpixel * subpixel * (3.0 - 2.0 * subpixel);
    subpixel = subpixel * subpixel * 0.5;
    return displaySample(scene, uv + across * max(shift, subpixel), pixel);
#endif
#endif
}
