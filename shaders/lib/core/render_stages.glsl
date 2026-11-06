// Keep loader-specific draw phases out of geometry and lighting algorithms.
#ifndef LIB_RENDER_STAGES_GLSL
#define LIB_RENDER_STAGES_GLSL

// Iris publishes symbolic phases. OptiFine J9 uses the fallback ordinals below.
bool isOpaqueTerrainStage() {
#ifdef IS_IRIS
    return renderStage == MC_RENDER_STAGE_TERRAIN_SOLID
        || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
        || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
        || renderStage == MC_RENDER_STAGE_TRIPWIRE;
#else
    return renderStage == 8 || renderStage == 9;
#endif
}

bool isCutoutTerrainStage() {
#ifdef IS_IRIS
    return renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
        || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
        || renderStage == MC_RENDER_STAGE_TRIPWIRE;
#else
    return renderStage == 9;
#endif
}

bool isTranslucentTerrainStage() {
#ifdef IS_IRIS
    return renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
#else
    return renderStage == 16;
#endif
}

bool isTerrainStage() {
    return isOpaqueTerrainStage() || isTranslucentTerrainStage();
}

// Native particles are camera-facing quads, not inferred terrain planes.
bool isParticleStage() {
#ifdef IS_IRIS
    return renderStage == MC_RENDER_STAGE_PARTICLES;
#else
    return renderStage == 18;
#endif
}

bool isActorStage() {
#ifdef IS_IRIS
    return renderStage == MC_RENDER_STAGE_ENTITIES
        || renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES;
#else
    return renderStage == 10 || renderStage == 11;
#endif
}

// Sodium batches cutout sprites into TERRAIN_SOLID on modern Minecraft.
// Classify their actual atlas coverage instead of assuming solid phase = cube.
bool isMaskedTerrainSurface(sampler2D atlas, vec2 centre, vec2 halfSize) {
    if (isCutoutTerrainStage()) {
        return true;
    }
#ifdef IS_IRIS
    if (isOpaqueTerrainStage() && all(greaterThan(halfSize, vec2(0.0)))) {
        vec2 pixels = halfSize * 2.0 * vec2(textureSize(atlas, 0));
        float level = log2(max(max(pixels.x, pixels.y), 1.0));
        return textureLod(atlas, centre, level).a < 0.999;
    }
#endif
    return false;
}

#endif
