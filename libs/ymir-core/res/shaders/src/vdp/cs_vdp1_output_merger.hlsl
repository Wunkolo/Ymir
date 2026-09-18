#include "vdp1_defs.hlsli"
#include "vdp1_common_params.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

// Shader specialization macros:
// - POLYSPEC_TRANSPARENT_MESH: 0=checkerboard mesh; 1=transparent mesh
// - POLYSPEC_MERGE_MODE:
//     0 = Copy (Replace, Half-Luminance)
//     1 = Right-shift (Shadow)
//     2 = OIT (Half-Transparency)
//
// Implementation notes:
// - Works on 32-bit units at a time

// Modify these to adjust IntelliSense highlighting
#ifdef __INTELLISENSE__
#define POLYSPEC_TRANSPARENT_MESH 0
#define POLYSPEC_MERGE_MODE       2
#endif

cbuffer RenderParamsBuffer : register(b0) {
    CommonRenderParams g_commonParams;
}

RWByteAddressBuffer g_fbramOut : register(u1);
RWBuffer<uint> g_internalSpriteOut : register(u2);

// ---------------------------------------------------------------------------------------------------------------------
// Parameters

static const uint2 fbSize = uint2(
    512u << BitExtract(g_commonParams.displayParams, 0, 1),
    256u << BitExtract(g_commonParams.displayParams, 1, 1)
);
static const bool pixel8Bits = BitTest(g_commonParams.displayParams, 2);
static const bool doubleDensity = BitTest(g_commonParams.displayParams, 3);
static const bool dblInterlaceEnable = BitTest(g_commonParams.displayParams, 4);
static const bool dblInterlaceDrawLine = BitTest(g_commonParams.displayParams, 5);
static const uint drawFB = BitExtract(g_commonParams.displayParams, 7, 1);

static const uint fbOffset = drawFB * kVDP1FBRAMSize;

static const bool deinterlace = BitTest(g_commonParams.enhancements, 0);

// ---------------------------------------------------------------------------------------------------------------------
// Mergers

#if POLYSPEC_MERGE_MODE == 0
// ----------------------------------------------------------------------------
// Copy (Replace, Half-Luminance)

void Merge8(uint2 pos) {
    const uint inOffset = pos.x * 4 + pos.y * fbSize.x;

    // Read and clear internal outputs
    const uint out0 = g_internalSpriteOut[inOffset + 0];
    const uint out1 = g_internalSpriteOut[inOffset + 1];
    const uint out2 = g_internalSpriteOut[inOffset + 2];
    const uint out3 = g_internalSpriteOut[inOffset + 3];

    const uint counter0 = BitExtract(out0, 16, 16);
    const uint counter1 = BitExtract(out1, 16, 16);
    const uint counter2 = BitExtract(out2, 16, 16);
    const uint counter3 = BitExtract(out3, 16, 16);
    if (counter0 == 0 && counter1 == 0 && counter2 == 0 && counter3 == 0) {
        // Nothing written to these pixels
        return;
    }
    g_internalSpriteOut[inOffset + 0] = 0;
    g_internalSpriteOut[inOffset + 1] = 0;
    g_internalSpriteOut[inOffset + 2] = 0;
    g_internalSpriteOut[inOffset + 3] = 0;

    const uint outOffset = inOffset;
    uint fbramValue = g_fbramOut.Load(outOffset + fbOffset);
    if (counter0 != 0) {
        fbramValue &= ~0xFFu;
        fbramValue |= BitExtract(out0, 0, 8);
    }
    if (counter1 != 0) {
        fbramValue &= ~0xFF00u;
        fbramValue |= BitExtract(out1, 0, 8) << 8u;
    }
    if (counter2 != 0) {
        fbramValue &= ~0xFF0000u;
        fbramValue |= BitExtract(out2, 0, 8) << 16u;
    }
    if (counter3 != 0) {
        fbramValue &= ~0xFF000000u;
        fbramValue |= BitExtract(out3, 0, 8) << 24u;
    }
    g_fbramOut.Store(outOffset + fbOffset, fbramValue);
}

void Merge16(uint2 pos) {
    const uint inOffset = pos.x * 2 + pos.y * fbSize.x;

    // Read and clear internal outputs
    const uint out0 = g_internalSpriteOut[inOffset + 0];
    const uint out1 = g_internalSpriteOut[inOffset + 1];

    const uint counter0 = BitExtract(out0, 16, 16);
    const uint counter1 = BitExtract(out1, 16, 16);
    if (counter0 == 0 && counter1 == 0) {
        // Nothing written to these pixels
        return;
    }
    g_internalSpriteOut[inOffset + 0] = 0;
    g_internalSpriteOut[inOffset + 1] = 0;

    const uint outOffset = inOffset * 2;
    uint fbramValue = g_fbramOut.Load(outOffset + fbOffset);
    if (counter0 != 0) {
        fbramValue &= ~0xFFFFu;
        fbramValue |= BitExtract(out0, 0, 16);
    }
    if (counter1 != 0) {
        fbramValue &= ~0xFFFF0000u;
        fbramValue |= BitExtract(out1, 0, 16) << 16u;
    }
    g_fbramOut.Store(outOffset + fbOffset, fbramValue);
}

#elif POLYSPEC_MERGE_MODE == 1
// ----------------------------------------------------------------------------
// Right-shift (Shadow)

void Merge8(uint2 pos) {
    // Shadow does not apply to 8-bit mode.
}

void Merge16(uint2 pos) {
    const uint inOffset = pos.x * 2 + pos.y * fbSize.x;

    // Read and clear internal outputs
    const uint shift0 = min(g_internalSpriteOut[inOffset + 0], 5);
    const uint shift1 = min(g_internalSpriteOut[inOffset + 1], 5);
    if (shift0 == 0 && shift1 == 0) {
        // Nothing written to these pixels
        return;
    }
    g_internalSpriteOut[inOffset + 0] = 0;
    g_internalSpriteOut[inOffset + 1] = 0;

    const uint outOffset = inOffset * 2;
    uint fbramValue = g_fbramOut.Load(outOffset + fbOffset);
    if (shift0 != 0) {
        uint4 color = Uint16ToColor555(BitExtract(fbramValue, 0, 16));
        if (color.a != 0u) {
            color.rgb >>= shift0;
            fbramValue &= ~0xFFFFu;
            fbramValue |= Color555ToUint16(color);
        }
    }
    if (shift1 != 0) {
        uint4 color = Uint16ToColor555(BitExtract(fbramValue, 16, 16));
        if (color.a != 0u) {
            color.rgb >>= shift1;
            fbramValue &= ~0xFFFF0000u;
            fbramValue |= Color555ToUint16(color) << 16u;
        }
    }
    g_fbramOut.Store(outOffset + fbOffset, fbramValue);
}

#elif POLYSPEC_MERGE_MODE == 2
// ----------------------------------------------------------------------------
// OIT (Half-Transparency)

void Merge8(uint2 pos) {
    // Half-Transparency does not apply to 8-bit mode.
}

void Merge16(uint2 pos) {
    // TODO: implement
}

#endif

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(8, 8, 1)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    if (pixel8Bits) {
        Merge8(id.xy);
    } else {
        Merge16(id.xy);
    }
}
