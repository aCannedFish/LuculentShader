#ifndef LUCULENT_WATER_STORAGE_LAYOUT
#define LUCULENT_WATER_STORAGE_LAYOUT
// Shared geometry extent and storage sizes. Column masks use 32 height bands;
// macro cells remain four blocks wide and never act as geometric surfaces.
const ivec3 waterFarSize = ivec3(256, 128, 256);
const ivec3 waterMacroSize = waterFarSize / 4;
const int waterMacroCount = waterMacroSize.x * waterMacroSize.y * waterMacroSize.z;
const int waterSmallColumns = (waterFarSize.x / 4) * (waterFarSize.z / 4);
const int waterLargeColumns = (waterFarSize.x / 16) * (waterFarSize.z / 16);
const int waterColumnCount = waterSmallColumns + waterLargeColumns;
const int waterHeightBand = waterFarSize.y / 32;
const int waterPlantSide = 512;
const int waterPlantCells = waterPlantSide * waterPlantSide;
const int waterTriangleSlots = 32768;
const int waterTriangleNodes = 131072;
const int waterTriangleWords = waterTriangleSlots * 20 + waterTriangleNodes * 2 + waterMacroCount;
#endif
