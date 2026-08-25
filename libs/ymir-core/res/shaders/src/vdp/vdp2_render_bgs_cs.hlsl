#include "vdp2_common_params.hlsli"
#include "vdp2_render_params_layer.hlsli"

#include "vdp2_defs.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

cbuffer CommonRenderParamsBuffer : register(b0) {
    CommonRenderParams g_commonParams;
}

ByteAddressBuffer vram : register(t1);
Buffer<uint4> cramColor : register(t2);
StructuredBuffer<LayerRenderParams> layerParams : register(t3);

RWTexture2DArray<uint4> bgOut : register(u0);

// ---------------------------------------------------------------------------------------------------------------------
// Utilities

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
    // TODO
    /*if (!hiResH)*/ {
        start.x >>= 1;
        end.x >>= 1;
    }

    const int2 spos = int2(pos);
    const bool inside = all(spos >= start) && all(spos <= end);
    return inside != invert;
}

bool InsideSpriteWindow(bool invert, uint2 pos) {
    return BitTest(bgOut[uint3(pos, 6)].a, kPixelAttrBitSpriteShadowWindow) != invert;
}

bool InsideWindows(LayerWindowParams layerWindows, uint2 pos) {
    const bool windowLogicAND = layerWindows.windowLogicAnd;
    const bool window0Enable = layerWindows.window0Enable;
    const bool window0Invert = layerWindows.window0Invert;
    const bool window1Enable = layerWindows.window1Enable;
    const bool window1Invert = layerWindows.window1Invert;

    // If no windows are enabled, consider the pixel outside of windows
    if (!window0Enable && !window1Enable) {
        return false;
    }

    const uint2 screenPos = pos; //ScaleDown(pos);

    bool inside = windowLogicAND;
    if (window0Enable) {
        const bool insideW0 = InsideWindow(layerParams[0].windows[0], window0Invert, screenPos);
        if (windowLogicAND) {
            inside = inside && insideW0;
        } else {
            inside = inside || insideW0;
        }
    }
    if (window1Enable) {
        const bool insideW1 = InsideWindow(layerParams[0].windows[1], window1Invert, screenPos);
        if (windowLogicAND) {
            inside = inside && insideW1;
        } else {
            inside = inside || insideW1;
        }
    }

    return inside;
}

bool InsideWindows(LayerWindowParamsS layerWindows, uint2 pos) {
    const bool windowLogicAND = layerWindows.base.windowLogicAnd;
    const bool window0Enable = layerWindows.base.window0Enable;
    const bool window0Invert = layerWindows.base.window0Invert;
    const bool window1Enable = layerWindows.base.window1Enable;
    const bool window1Invert = layerWindows.base.window1Invert;
    const bool spriteWindowEnable = layerWindows.spriteWindowEnable;
    const bool spriteWindowInvert = layerWindows.spriteWindowInvert;

    // If no windows are enabled, consider the pixel outside of windows
    if (!window0Enable && !window1Enable && !spriteWindowEnable) {
        return false;
    }

    const uint2 screenPos = pos; //ScaleDown(pos);

    bool inside = windowLogicAND;
    if (window0Enable) {
        const bool insideW0 = InsideWindow(layerParams[0].windows[0], window0Invert, screenPos);
        if (windowLogicAND) {
            inside = inside && insideW0;
        } else {
            inside = inside || insideW0;
        }
    }
    if (window1Enable) {
        const bool insideW1 = InsideWindow(layerParams[0].windows[1], window1Invert, screenPos);
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
// NBG drawing

uint4 DrawNBG(uint2 pos, // pixel coordinates
              uint index // NBG index (0 to 3)
             ) {
    NBGParams params = layerParams[0].nbg[index];
    if (!params.base.enabled) {
        return kTransparentPixel;
    }

    // pos.y = GetY(pos.y, true);
    // if (deinterlace && interlaceMode == kInterlaceModeSingleDensity) {
    //     pos.y >>= 1;
    // }

    if (InsideWindows(params.base.windowParams, pos)) {
        return kTransparentPixel;
    }

    const uint value = vram.Load(pos.x * 4 + pos.y * 1024);
    return uint4(
        BitExtract(value, 0, 8) ^ index,
        BitExtract(value, 8, 8) ^ index,
        BitExtract(value, 16, 8) ^ index,
        BitExtract(value, 24, 8) ^ index
    );
}

// ---------------------------------------------------------------------------------------------------------------------
// RBG drawing

uint4 DrawRBG(uint2 pos, // pixel coordinates
              uint index // RBG index (0 to 1)
             ) {
    RBGParams params = layerParams[0].rbg[index];
    if (!params.base.enabled) {
        return kTransparentPixel;
    }
    return uint4(pos.x, pos.y, index, 1);
}

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(32, 1, 6)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    const uint2 drawCoord = uint2(id.x, id.y + g_commonParams.startY /*+ ScaleUp(g_commonParams.startY)*/);
    const uint3 outCoord = uint3(drawCoord.x, drawCoord.y /*GetY(drawCoord.y, false)*/, id.z);
    if (id.z <= 3) {
        bgOut[outCoord] = DrawNBG(drawCoord, id.z);
    } else if (id.z <= 5) {
        bgOut[outCoord] = DrawRBG(drawCoord, id.z - 4);
    }
}
