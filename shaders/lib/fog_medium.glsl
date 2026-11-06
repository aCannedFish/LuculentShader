#ifndef LUCULENT_FOG_MEDIUM
#define LUCULENT_FOG_MEDIUM

// Air has no artificial fade tied to chunk/render distance. Participating
// media are integrated by their own volume passes. Lava and the native
// Nether/End atmosphere retain their distance-based extinction.
float getFogFactor(float distanceToCamera) {
    float distance = max(distanceToCamera, 0.0);
    if (isEyeInWater == 2) {
        return 1.0 - exp(-distance * 4.0);
    }
    if (isEyeInWater == 1) {
        return 0.0;
    }
#if SIMPLE_DIMENSION != 0
    float density = SIMPLE_DIMENSION == -1 ? NETHER_FOG_DENSITY : END_FOG_DENSITY;
    return 1.0 - exp(-distance * density * FOG_DENSITY);
#else
    return 0.0;
#endif
}

#endif
