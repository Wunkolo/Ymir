#include "vdp2_common_params.hlsli"
#include "vdp2_render_params_layer.hlsli"

#include "vdp2_defs.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

cbuffer CommonRenderParams : register(b0) {
    CommonRenderParams g_commonParams;
}

StructuredBuffer<LayerRenderParams> layerParams : register(t1);
ByteAddressBuffer vram : register(t2);
Texture2DArray<uint> spriteAttrsIn : register(t3);

RWTexture2D<uint4> colorCalcWindowOut : register(u0);

// ---------------------------------------------------------------------------------------------------------------------
// Parameters

static const uint interlaceMode = BitExtract(g_commonParams.displayParams, 2, 2);
static const uint oddField = BitExtract(g_commonParams.displayParams, 4, 1);
static const bool exclusiveMonitor = BitTest(g_commonParams.displayParams, 5);
static const bool hiResH = BitTest(g_commonParams.displayParams, 8);

static const bool deinterlace = BitTest(g_commonParams.enhancements, 0);

// ---------------------------------------------------------------------------------------------------------------------
// Utilities

uint GetY(uint y) {
    const bool interlaced = interlaceMode >= kInterlaceModeSingleDensity;

    if (!deinterlace && interlaced && !exclusiveMonitor) {
        return (y << 1) | oddField;
    } else {
        return y;
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Windows

bool InsideWindow(GlobalWindowParams window, bool invert, uint2 pos) {
    int2 start = window.start;
    int2 end = window.end;

    // Read line window if enabled
    if (window.lineWindowTableEnable) {
        const uint address = window.lineWindowTableAddress + pos.y * 4;
        start.x = Read16(vram, address + 0);
        end.x = Read16(vram, address + 2);
    }

    start.x = SignExtend(start.x, 16);
    end.x = SignExtend(end.x, 16);
    start.y = SignExtend(start.y, 16);
    end.y = SignExtend(end.y, 16);

    // Some games set out-of-range window parameters and expect them to work.
    // It seems like window coordinates should be signed...
    //
    // Panzer Dragoon 2 Zwei:
    //   0000 to FFFE -> empty window
    //   FFFE to 02C0 -> full line
    //
    // Panzer Dragoon Saga:
    //   0000 to FFFF -> empty window
    //
    // Snatcher:
    //   FFFC to 0286 -> full line
    //
    // Handle these cases here
    if (start.x < 0) {
        start.x = 0;
    }
    if (end.x < 0) {
        if (start.x >= end.x) {
            start.x = 0x3FF;
        }
        end.x = 0;
    }

    // For normal screen modes, X coordinates don't use bit 0
    if (!hiResH) {
        start.x >>= 1;
        end.x >>= 1;
    }

    const int2 spos = int2(pos);
    const bool inside = all(spos >= start) && all(spos <= end);
    return inside != invert;
}

bool InsideSpriteWindow(bool invert, uint2 pos) {
    return BitTest(spriteAttrsIn[uint3(pos, 0)], kSpriteAttrBitShadowWindow) != invert;
}

bool InsideWindows(uint windowParams, uint2 pos) {
    const bool windowLogicAND = BitTest(windowParams, 0);
    const bool window0Enable = BitTest(windowParams, 1);
    const bool window0Invert = BitTest(windowParams, 2);
    const bool window1Enable = BitTest(windowParams, 3);
    const bool window1Invert = BitTest(windowParams, 4);
    const bool spriteWindowEnable = BitTest(windowParams, 5);
    const bool spriteWindowInvert = BitTest(windowParams, 6);

    // If no windows are enabled, consider the pixel outside of windows
    if (!window0Enable && !window1Enable && !spriteWindowEnable) {
        return false;
    }

    bool inside = windowLogicAND;
    if (window0Enable) {
        const bool insideW0 = InsideWindow(layerParams[0].windows[0], window0Invert, pos);
        if (windowLogicAND) {
            inside = inside && insideW0;
        } else {
            inside = inside || insideW0;
        }
    }
    if (window1Enable) {
        const bool insideW1 = InsideWindow(layerParams[0].windows[1], window1Invert, pos);
        if (windowLogicAND) {
            inside = inside && insideW1;
        } else {
            inside = inside || insideW1;
        }
    }
    if (spriteWindowEnable) {
        const bool insideSW = InsideSpriteWindow(spriteWindowInvert, pos);
        if (windowLogicAND) {
            inside = inside && insideSW;
        } else {
            inside = inside || insideSW;
        }
    }

    return inside;
}

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(32, 1, 1)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    const uint2 drawCoord = uint2(id.x, id.y + g_commonParams.startY);
    const uint3 outCoord = uint3(drawCoord.x, GetY(drawCoord.y), id.z);
    colorCalcWindowOut[outCoord.xy] = InsideWindows(g_commonParams.windows >> 5, drawCoord);
}
