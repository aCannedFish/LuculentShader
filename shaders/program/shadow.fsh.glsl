#define SIMPLE_VARYING in
layout(location=0) out vec4 fullOut0;
layout(location=1) out vec4 fullOut1;
layout(location=2) out vec4 fullOut2;
layout(location=3) out vec4 fullOut3;
layout(location=4) out vec4 fullOut4;

/* 日月阴影深度阶段。按贴图 alpha 拒绝镂空部分，避免树叶和植物被当作完整实心面。
 * shadowcolor0 记录最近投影体：发光方块写显示空间颜色 (a=0.75，8 位保留暗部精度)，玻璃写透射色 (a=0.5)，
 * 水等其余半透明体写 (0, 0.5)，薄植被写 (0, 0.25)，不透明体写 (0, 1)。
 * 薄植被仅在其自身的逆光着色时使用类别；普通接收面仍按不透明遮挡处理。
 * 其余 alpha（含白色清屏值）一律视为不透明，
 * 保证类别缺失时阴影只会退回普通遮挡，不会被误补光。
 * OptiFine 会在 fullOut0 写入处注入 `if (a < alphaTestRef) discard;`，
 * 写 a=0 会连深度一起丢掉，不透明体便不再投影；所有标记的 alpha 都必须高于该阈值。
 */
/* DRAWBUFFERS:01 */

/* 全局渲染设置。集中定义加载器常量、缓冲格式和可调宏；各程序共享同一组默认值。
 * 游戏内选项由 shaders.properties 分组，用户选择由加载器保存。
 */
#include "/settings.glsl"

/* 加载器输入声明。集中定义相机、时间、天气、光照、深度与视图/阴影矩阵 uniform。
 */
#include "/lib/uniforms.glsl"

/* 坐标变换。统一视图、相机相对世界、绝对世界、投影和阴影空间的转换约定。
 */
#include "/lib/core/space_shadow.glsl"

uniform sampler2D gtexture;
uniform vec4 spriteBounds;

SIMPLE_VARYING vec2 vTexCoord;
SIMPLE_VARYING vec4 vColor;
SIMPLE_VARYING vec3 vShadowPosition;
SIMPLE_VARYING vec3 vCasterNormal;
SIMPLE_VARYING vec2 vCasterLight;
flat SIMPLE_VARYING int vWaterFaceParity;
SIMPLE_VARYING float vCaster;

flat in int vEntityTriangle;

void main() {
    // 在 alpha 丢弃前求导，保证叶片边缘仍有完整的导数四像素组。
    vec3 dx = dFdx(vShadowPosition);
    vec3 dy = dFdy(vShadowPosition);
    vec2 uvDx = dFdx(vTexCoord);
    vec2 uvDy = dFdy(vTexCoord);
    vec4 colourDx = dFdx(vColor);
    vec4 colourDy = dFdy(vColor);
    vec2 lmDx = dFdx(vCasterLight);
    vec2 lmDy = dFdy(vCasterLight);
    vec3 plane = cross(dx, dy);
    float planeScale = max(max(abs(plane.x), abs(plane.y)), abs(plane.z));
    vec2 uv = vTexCoord;
    vec4 vertexColour = vColor;
    vec2 nativeLight = vCasterLight;
    gl_FragDepth = gl_FragCoord.z;
    if (abs(plane.z) > max(1e-20, planeScale * 0.00001)) {
        vec2 distorted = gl_FragCoord.xy / shadowTextureResolution() * 2.0 - 1.0;
        vec2 offset = undistortShadow(distorted) - vShadowPosition.xy;
        // Match material attributes to the very same undistorted position as depth.
        vec2 screenOffset = inverse(mat2(dx.xy, dy.xy)) * offset;
        uv += uvDx * screenOffset.x + uvDy * screenOffset.y;
        vertexColour += colourDx * screenOffset.x + colourDy * screenOffset.y;
        nativeLight += lmDx * screenOffset.x + lmDy * screenOffset.y;
        gl_FragDepth = clamp((vShadowPosition.z - dot(plane.xy, offset) / plane.z) * 0.5 + 0.5, 0.0, 1.0);
    }
    vec4 albedo = textureGrad(gtexture, uv, uvDx, uvDy) * vertexColour;
    if (albedo.a < alphaTestRef) discard;

    // 不透明表面保留原生材质颜色，供反射命中重建使用；alpha 类别不变。
    vec4 caster = vec4(albedo.rgb, 1.0);
    if (vCaster > 3.5) {
        caster = vec4(albedo.rgb, 0.25);
    } else if (vCaster > 2.5) {
        caster = vec4(0.0, 0.0, 0.0, 0.5);
    } else if (vCaster > 1.5) {
        // 与 Mod 的玻璃吸收同一经验式：饱和色调透射对应色光，浅色接近无色。
        float peak = max(max(albedo.r, albedo.g), albedo.b);
        vec3 hue = albedo.rgb / max(peak, 0.001);
        vec3 tint = (0.35 + 0.60 * peak) * (0.12 + 0.88 * pow(hue, vec3(1.5)));
        caster = vec4(clamp(tint, 0.0, 1.0), 0.5);
    } else if (vCaster > 0.5) {
        caster = vec4(albedo.rgb, 0.75);
    }
    fullOut0 = caster;
    // A shadow texel can straddle a native block edge. Retain its submitted
    // owner, even when nonlinear rasterization places the texel past that edge.
    vec3 faceNormal = normalize(vCasterNormal);
    vec2 oct = round(encodeNormal(faceNormal) * vec2(254.0, 255.0));
    vec3 axisWeight = abs(faceNormal);
    int axis = axisWeight.x > max(axisWeight.y, axisWeight.z) ? 0 : (axisWeight.y > axisWeight.z ? 1 : 2);
    if (vWaterFaceParity >= 0 && axisWeight[axis] > 0.99995) {
        int axisCode = axis * 2 + int(faceNormal[axis] < 0.0);
        oct = vec2(255.0, float(vWaterFaceParity * 8 + axisCode));
    }
    vec2 levels = round(clamp(nativeLight, 0.0, 1.0) * 15.0);
    bool terrain = isTerrainStage();
    vec2 extent = spriteBounds.zw - spriteBounds.xy;
    bool localSprite = all(greaterThan(extent, vec2(0.0)))
        && any(notEqual(textureSize(gtexture, 0), atlasSize));
    vec2 atlasUv = localSprite ? spriteBounds.xy + clamp(uv, 0.0, 1.0) * extent : uv;
    vec2 address = round(clamp(atlasUv, 0.0, 1.0) * 65535.0);
    if (!terrain) address.x = float(vEntityTriangle + 1);
    vec4 tint = round(clamp(vec4(terrain ? vertexColour.rgb : albedo.rgb, vertexColour.a), 0.0, 1.0) * 15.0);
    float packedTint = dot(tint, vec4(1.0, 16.0, 256.0, 4096.0));
    vec3 record = vec3(address + oct * 65536.0, packedTint + (levels.x + levels.y * 16.0) * 65536.0);
    if (!terrain) record.x = -1.0 - record.x;
    if (vCaster > 3.5) record.y = -1.0 - record.y;
    float opaque = vCaster > 1.5 && vCaster < 3.5 ? 0.0 : 1.0;
    fullOut1 = vec4(record * opaque, opaque);
}

