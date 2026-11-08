# 来源

## 月面

`shaders/textures/sky-noise.png` 的月面区域由 NASA Scientific Visualization Studio 的 CGI Moon Kit 月球颜色图缩小为 512×256 后打包。原作者为 Ernie Wright，数据来自 Lunar Reconnaissance Orbiter 的 LROC。项目使用的原始文件为 `lroc_color_2k.jpg`，不对其宣称额外的科研精度。

- [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/)
- [原始文件](https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_2k.jpg)
- [NASA SVS 使用条件](https://svs.gsfc.nasa.gov/help/)

NASA SVS 说明未另行标注的内容属于公共领域，可下载、使用和再分发。月面数据按其来源条件使用，不作为项目原创 MIT 代码的一部分重新授权。项目与 NASA 不存在背书或合作关系。图集中的云噪声由项目程序确定性生成。

## 接口

实现与配置参考以下接口及算法资料：

- [OptiFine Shader 接口](https://github.com/sp614x/optifine/blob/master/OptiFineDoc/doc/shaders.txt)
- [LabPBR 1.3 材质标准](https://github.com/shaderLABS/LabPBR/wiki)
- [Filament 透射与吸收材质](https://google.github.io/filament/main/materials.html)
- [SIGGRAPH 2016 实时体积云](https://advances.realtimerendering.com/s2016/)
- [NVIDIA FXAA 算法说明](https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf)：参考显示空间边缘检测、端点搜索和子像素重建方法。
- [SIGGRAPH 2014 实时渲染课程](https://www.advances.realtimerendering.com/s2014/index.html)：参考时域抗锯齿的 HDR 累积、重投影、历史拒绝和后处理顺序；本项目的实现独立编写。
- [Iris 缓冲保留接口](https://shaders.properties/current/reference/constants/buffer_clear/)：参考持久颜色附件及下一帧历史的接口约定。
- [Iris 区块渐入接口](https://shaders.properties/current/reference/attributes/mc_chunkfade/)：从加载器读取新区块的原生渐入进度。
- [Iris 世界与天气接口](https://shaders.properties/current/reference/uniforms/world/)及[几何通道接口](https://shaders.properties/current/reference/programs/gbuffers/)：接入原生闪电位置及电弧几何，体积照明与 HDR 扩散独立实现。
- [Complementary Reimagined](https://github.com/ComplementaryDevelopment/ComplementaryReimagined)：对照本机 r5.5.1 的重投影、邻域裁切和天空边界融合思路；算法独立适配，未引入其材质或美术资产。
- [Photon](https://github.com/sixthsurge/photon)：对照本机源码的打包 Bloom 降采样、圆盘景深和运动模糊组织，保留本项目的颜色、深度与历史接口。
- Derivative Main d24.4.14（本机安装包）：参考体积雾的高度衰减、三维密度团和透射率积分思路，独立适配至现有体积管线；不分发其源码或美术资产。
- [Iris Shader 教程](https://tt432.github.io/iris-shader-tutorial/)：参考水体通道分工、屏幕空间反射与后处理组织。
- [BSL Shaders](https://bitslablab.com/bslshaders/)（CaptTatsu）：本项目依据本机 BSL Standard v7.0p1 的步进、细化、误差半径、屏幕边界混合与快速 FXAA 参数独立适配；反射波纹参考其五层双向噪声、远波与法线衰减，水面调色参考 128/192/255 配比，相机速度模糊限定在倒影上。颜色、深度、天空及水面输入接入 Luculent 原有管线。未分发 BSL 原包或其美术资产。
- [GPU Gems 3 空间划分](https://developer.nvidia.com/gpugems/gpugems3/part-v-physics-simulation/chapter-32-broad-phase-collision-detection-cuda)：参考保守候选索引与精确几何检查的分工。
- [Narkowicz 的 ACES 曲线拟合](https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/)：保留其简化拟合系数，仅映射亮度并加入本项目的色域约束。原作者允许按 CC0 或 MIT 使用该拟合。

上述项目和资料维持各自的著作权与许可。本项目未将 Minecraft、OptiFine 或用户存档纳入源代码及发布包。
