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
// Parameters

static const uint interlaceMode = BitExtract(g_commonParams.displayParams, 2, 2);
static const uint oddField = BitExtract(g_commonParams.displayParams, 4, 1);
static const bool exclusiveMonitor = BitTest(g_commonParams.displayParams, 5);
static const bool hiResH = BitTest(g_commonParams.displayParams, 8);
static const bool palMode = BitTest(g_commonParams.displayParams, 9);
static const uint hreso = BitExtract(g_commonParams.displayParams, 10, 3);
static const uint vreso = BitExtract(g_commonParams.displayParams, 13, palMode ? 2 : 1);
static const uint displayResH = kResolutionsH[hreso & 3u]; // 3rd bit intentionally ignored
static const uint displayResV = exclusiveMonitor ? 480 : kResolutionsV[vreso];

static const bool deinterlace = BitTest(g_commonParams.enhancements, 0);
static const bool transparentMeshes = BitTest(g_commonParams.enhancements, 1);

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

    // uint2 fracScreenPos = pos * scaleStep;
    // uint2 screenPos = fracScreenPos >> kScaleBits;
    uint2 screenPos = pos;

    const uint2 pageShift = params.base.pageShift;
    const uint twoWordChar = params.base.twoWordChar;
    const uint cellSizeShift = params.base.cellSizeShift;
    const uint pageSize = kPageSizes[cellSizeShift][twoWordChar];
    const bool mosaicEnable = params.base.mosaicEnable;
    const bool vcellScrollEnable = params.vcellScrollEnable;

    uint2 baseFracScroll = uint2(0, 0);
    uint2 scrollInc = params.scrollInc;

    // Apply line scroll table effects on NBG0 and NBG1 if enabled
    if (index <= 1 && (params.lineScrollXEnable || params.lineScrollYEnable || params.lineZoomEnable)) {
        const uint lineScrollTableAddress = params.lineScrollTableAddress << 1;
        const uint lineScrollIntervalShift = params.lineScrollInterval;
        const bool lineScrollXEnable = params.lineScrollXEnable;
        const bool lineScrollYEnable = params.lineScrollYEnable;
        const bool lineZoomEnable = params.lineZoomEnable;

        // Determine offsets for each entry and intervals between sets of entries
        // TODO: make this relative to startY for games that change line scroll table flags mid-frame, if any
        const uint lineScrollXOffset = 0; // if present, it's always the first entry
        uint lineScrollYOffset = 0;
        uint lineZoomOffset = 0;
        uint lineScrollTableInc = 0;
        if (lineScrollXEnable) {
            lineScrollTableInc += 4;
        }
        if (lineScrollYEnable) {
            lineScrollYOffset = lineScrollTableInc;
            lineScrollTableInc += 4;
        }
        if (lineZoomEnable) {
            lineZoomOffset = lineScrollTableInc;
            lineScrollTableInc += 4;
        }

        const uint baseTableAddr = lineScrollTableAddress + (screenPos.y >> lineScrollIntervalShift) * lineScrollTableInc;
        if (lineScrollXEnable) {
            const uint tableAddr = baseTableAddr + lineScrollXOffset;
            baseFracScroll.x = BitExtract(Read32(vram, tableAddr), 8, 19);
        }
        if (lineScrollYEnable) {
            const uint tableAddr = baseTableAddr + lineScrollYOffset;
            baseFracScroll.y = BitExtract(Read32(vram, tableAddr), 8, 19);
            pos.y &= (1u << lineScrollIntervalShift) - 1u; // reset cumulative scrollIncV increment
            // fracScreenPos.y = pos.y * scaleStep;
            // screenPos.y = fracScreenPos.y >> kScaleBits;
            screenPos.y = pos.y;
        }
        if (lineZoomEnable) {
            const uint tableAddr = baseTableAddr + lineZoomOffset;
            scrollInc.x = BitExtract(Read32(vram, tableAddr), 8, 11);
        }
    }

    if (vcellScrollEnable && !mosaicEnable) {
        const uint vcellScrollOffset = params.vcellScrollOffset << 2;
        const bool vcellScrollDelay = params.vcellScrollDelay;
        const bool vcellScrollRepeat = params.vcellScrollRepeat;

        const uint scrollX = baseFracScroll.x >> 8;
        int offset = (screenPos.x + (scrollX & 7)) >> 3;
        if (vcellScrollRepeat && offset > 0) {
            --offset;
        }
        if (vcellScrollDelay) {
            --offset;
        }

        // TODO: if offset == -1, read from the end of the previous line (or end of frame if at topmost row of cells)
        const uint vcellScrollTableAddress = BitExtract(g_commonParams.vcellScroll, 0, 19);
        const uint vcellScrollInc = BitExtract(g_commonParams.vcellScroll, 19, 3) << 2u;
        const uint vcellAddress = vcellScrollTableAddress + offset * vcellScrollInc + vcellScrollOffset;
        const uint vcellScrollY = BitExtract(Read32(vram, vcellAddress), 8, 19);
        baseFracScroll.y += vcellScrollY;
    }

    const uint2 fracScrollPos = baseFracScroll + params.scrollAmount + scrollInc * screenPos;
    uint2 scrollPos = fracScrollPos >> 8;
    if (mosaicEnable) {
        const uint2 mosaic = uint2(BitExtract(g_commonParams.layerParams, 14, 4) + 1, BitExtract(g_commonParams.layerParams, 18, 4) + 1);
        scrollPos -= scrollPos % mosaic;
    }

    const bool bitmap = params.base.bitmap;
    if (bitmap) {
        // TODO: return FetchBitmapPixel(params, scrollPos);
        return uint4(scrollPos.xy, 1, 128);
    } else {
        const uint2 plane = (scrollPos >> (9u + pageShift)) & 1u;
        const uint pageBaseAddress = params.pageBaseAddresses[plane.x | (plane.y << 1u)];
        const uint bank = BitExtract(pageBaseAddress, 17, 2);
        const bool charPatDelay = BitTest(params.base.charPatDelay, bank);
        if (charPatDelay) {
            // Read previous character.
            // If we're at the start of the line, read last character from previous line.
            // If at the start of the screen, read last character in the screen.
            if (screenPos.x >= 8) {
                // Not at left edge of the screen - read character to the left
                scrollPos.x -= 8;
            } else {
                // Left edge of the screen - read rightmost character from previous row
                scrollPos.x += displayResH - 8;
                if (screenPos.y >= 8) {
                    // Not at top edge of the screen - read previous row
                    scrollPos.y -= 8;
                } else {
                    // At top edge of the screen - read last character read the previous screen
                    // TODO: read character from the previous screen (store on CPU side)
                    scrollPos.y += displayResV - 8;
                }
            }
        }
        // TODO: return FetchScrollNBGPixel(params, scrollPos);
        return uint4(scrollPos.xy, 0, 128);
    }
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
