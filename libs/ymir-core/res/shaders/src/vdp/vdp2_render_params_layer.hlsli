#ifndef YMIR_VDP_VDP2_RENDER_PARAMS_LAYER_HLSLI
#define YMIR_VDP_VDP2_RENDER_PARAMS_LAYER_HLSLI

// See C++ code for documentation on the fields

struct WindowParams {
    bool windowLogicAnd;
    bool window0Enable;
    bool window0Invert;
    bool window1Enable;
    bool window1Invert;
};

struct WindowParamsS {
    WindowParams base;
    bool spriteWindowEnable;
    bool spriteWindowInvert;
};

struct BaseBGParams {
    bool enabled;
    bool enableTransparency;
    bool bitmap;
    uint priorityNumber;
    uint priorityMode;
    uint specialFunctionSelect;
    uint cellSizeShift;
    uint colorFormat;
    uint cramOffset;
    uint supplScrollCharNum;
    uint supplPalNum;
    uint supplSpecialColorCalc;
    uint supplSpecialPriority;
    bool mosaicEnable;
    bool colorCalcEnable;
    bool extChar;
    bool twoWordChar;
    uint patNameAccess;
    uint charPatAccess;
    uint charPatDelay;
    uint vramDataOffset;
    uint specialColorCalcMode;
    uint2 pageShift;
    uint bitmapBaseAddress;
    WindowParamsS windowParams;
};

struct NBGParams {
    BaseBGParams base;
    uint2 bitmapSize;
    uint2 scrollAmount;
    uint2 scrollInc;
    uint pageBaseAddresses[4];
    bool vcellScrollEnable;
    bool lineScrollXEnable;
    bool lineScrollYEnable;
    bool lineZoomEnable;
    uint lineScrollInterval;
    uint lineScrollTableAddress;
    uint vcellScrollOffset;
    uint vcellScrollDelay;
    uint vcellScrollRepeat;
};

struct RBGParams {
    BaseBGParams base;
    uint screenOverProcess;
    uint screenOverPatternName;
    uint pageBaseAddresses[2][16];
};

struct LayerRenderParams {
    NBGParams nbg[4];
    RBGParams rbg[2];
};

#endif
