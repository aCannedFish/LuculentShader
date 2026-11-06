#define SIMPLE_VARYING out

in vec3 vaPosition;
in vec4 vaColor;
in vec3 vaNormal;
in vec2 vaUV0;
in ivec2 vaUV2;
uniform vec3 modelOffset;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat3 normalMatrix;
/* 相机位置决定的低频空气密度在全屏顶点上计算，避免每个体积片元重复读取
 * 相同的两个噪声纹素。各顶点的值一致，透视插值后仍为同一个帧内常量。
 */
/*
 * Continuous cloud density and inexpensive projected cloud shadows.
 * The tiled 64-cubed periodic field is baked by tools/build_sky_assets.py.
 * Weather changes cloud coverage and vertical profile; three Worley bands erode
 * the boundary without introducing a block lattice or per-frame shape popping.
 * A finite, camera-centred weather field fades into the horizon before its
 * boundary. View rays, environment lookups and projected shadows share it.
 */
#include "/lib/atmosphere/cloud_density_water.glsl"

SIMPLE_VARYING float vAirDensityModulation;

void main() {
    gl_Position = (projectionMatrix * modelViewMatrix * vec4(vaPosition + modelOffset, 1.0));
    vAirDensityModulation = mix(0.98, 1.02, cloudVolumeNoise(cameraPosition / 2048.0).r);
}

