// Sky and cloud radiance used when an optical ray reaches the environment.
#ifndef LIB_WATER_ENVIRONMENT_GLSL
#define LIB_WATER_ENVIRONMENT_GLSL
#include "/lib/atmosphere/clouds_water.glsl"

vec3 waterEnvironment(vec3 originWorld, vec3 rayWorld, float skyVisibility, bool celestial) {
#if SIMPLE_DIMENSION == 1
    return mix(dimensionAmbient(rayWorld) * AMBIENT_STRENGTH,
               skyAtmosphereRadiance(rayWorld) * 1.8, END_ATMOSPHERE * 0.65);
#elif SIMPLE_DIMENSION == -1
    return dimensionAmbient(rayWorld) * AMBIENT_STRENGTH;
#endif
    if (skyVisibility <= 0.001) {
        return vec3(0.0);
    }
    vec3 sky = skyAtmosphereRadiance(rayWorld) + skyStars(rayWorld);
    if (celestial) {
        sky += skyCelestialRadiance(rayWorld);
    }
#if WATER_REFLECTION_CLOUDS == 1
    // The sky strip already integrates clouds from the eye. Only integrate
    // them again when the reflected ray origin produces discernible parallax.
    float cloudRange = max(abs(CLOUD_HEIGHT - originWorld.y), 1.0) / max(rayWorld.y, 0.001);
    float parallax = length(originWorld - cameraPosition) / cloudRange;
    float detail = smoothstep(0.012, 0.035, parallax);
    vec4 cloud = cloudEnvironment(rayWorld);
    if (detail > 0.0) cloud = mix(cloud, traceVolumetricCloudsFrom(originWorld, rayWorld, CLOUD_DISTANCE, true), detail);
#else
    vec4 cloud = cloudEnvironment(rayWorld);
#endif
    return (cloud.rgb + sky * (1.0 - cloud.a)) * skyVisibility;
}
#endif
