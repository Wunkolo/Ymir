#ifndef YMIR_VDP_VDP1_POLYDRAW_PARAMS_HLSLI
#define YMIR_VDP_VDP1_POLYDRAW_PARAMS_HLSLI

// See C++ code for documentation on the fields

struct PolyDrawParams {
    uint numSpans;
    uint sysClip;
    uint userClip0;
    uint userClip1;
};

struct PolySpan {
    int2 coord0;
    int2 coord1;
    uint skip;
    uint attrs;

    uint3 gouraud0;
    uint3 gouraud1;

    uint cmdpmodcolr;
    uint cmdsizesrca;
};

#endif
