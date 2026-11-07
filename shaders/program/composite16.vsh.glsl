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
// 后处理全屏四边形；各通道的视口由 shaders.properties 指定。
void main() {
    gl_Position = (projectionMatrix * modelViewMatrix * vec4(vaPosition + modelOffset, 1.0));
}
