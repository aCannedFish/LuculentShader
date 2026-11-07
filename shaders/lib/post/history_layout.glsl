// 共享 C13 布局：介质、曝光/焦点、帧状态、投影状态及闪电位置/余辉。
#ifndef LIB_POST_HISTORY_LAYOUT_GLSL
#define LIB_POST_HISTORY_LAYOUT_GLSL
const int POST_METADATA_PIXELS = 5;
const float POST_HISTORY_SIGNATURE = 7440.0 + float(SIMPLE_DIMENSION) * 100.0
    + float(AA_MODE) + float(ENABLE_TAA) * 10.0;
const float POST_CAMERA_SIGNATURE = 9187.0 + float(SIMPLE_DIMENSION) * 16.0;
#endif
