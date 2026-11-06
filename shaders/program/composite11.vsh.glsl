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
/* 水下色调与雾色只依赖相机和入水深度，在全屏顶点上求值。
 * 各顶点读取相同的帧内元数据，避免所有片元重复计算相同的颜色和指数项。
 * UV 仍由片元位置重建，顶点只传递颜色常量。
 */
/* Water absorption and illuminated in-scattering shared by surface/underwater optics. */
#include "/lib/water/water_volume_water_vertex.glsl"

uniform sampler2D colortex4;
SIMPLE_VARYING vec3 vUnderwaterTint;
SIMPLE_VARYING vec3 vUnderwaterScatter;

void main() {
    gl_Position = (projectionMatrix * modelViewMatrix * vec4(vaPosition + modelOffset, 1.0));
    vUnderwaterTint = vec3(1.0);
    vUnderwaterScatter = vec3(0.0);
    if (isEyeInWater == 1) {
        vec4 medium = texture(colortex4, vec2(0.5) / vec2(viewWidth, viewHeight));
        vUnderwaterTint = underwaterSceneTint(medium.a, medium.r);
        vUnderwaterScatter = underwaterScatterColor(medium.a, medium.r);
    }
}

