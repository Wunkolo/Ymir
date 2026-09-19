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

#define POLYSPEC_SHADING_MODE_COPY  0
#define POLYSPEC_SHADING_MODE_SHIFT 1
#define POLYSPEC_SHADING_MODE_OIT   2

// Modify these to adjust IntelliSense highlighting
#ifdef __INTELLISENSE__
#define POLYSPEC_TRANSPARENT_MESH 0
#define POLYSPEC_MERGE_MODE       0
#endif

cbuffer RenderParamsBuffer : register(b0) {
    CommonRenderParams g_commonParams;
}

#if POLYSPEC_MERGE_MODE == POLYSPEC_SHADING_MODE_OIT
StructuredBuffer<OITFragment> g_fragments : register(t1);
RWByteAddressBuffer g_fbramOut : register(u1);
RWBuffer<uint> g_listHeads : register(u2);
#else
RWByteAddressBuffer g_fbramOut : register(u1);
RWBuffer<uint> g_internalSpriteOut : register(u2);
#endif

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

static const bool deinterlace = BitTest(g_commonParams.enhancements, 0);

static const uint fbOffset = drawFB * kVDP1FBRAMSize;

// ---------------------------------------------------------------------------------------------------------------------
// Mergers

#if POLYSPEC_MERGE_MODE == POLYSPEC_SHADING_MODE_COPY
// ----------------------------------------------------------------------------
// Copy (Replace, Half-Luminance)

void Merge8(uint2 pos, uint field) {
    const uint2 inPos = uint2(pos.x * 4, pos.y);
    const uint inOffset = inPos.x + inPos.y * fbSize.x + field * fbSize.x * fbSize.y;

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

    const uint outOffset = inPos.x + inPos.y * fbSize.x + field * kVDP1FBRAMSize * 2;
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

void Merge16(uint2 pos, uint field) {
    const uint2 inPos = uint2(pos.x * 2, pos.y);
    const uint inOffset = inPos.x + inPos.y * fbSize.x + field * fbSize.x * fbSize.y;

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

    const uint outOffset = (inPos.x + inPos.y * fbSize.x) * 2 + field * kVDP1FBRAMSize * 2;
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

#elif POLYSPEC_MERGE_MODE == POLYSPEC_SHADING_MODE_SHIFT
// ----------------------------------------------------------------------------
// Right-shift (Shadow)

void Merge8(uint2 pos, uint field) {
    // Shadow does not apply to 8-bit mode.
}

void Merge16(uint2 pos, uint field) {
    const uint2 inPos = uint2(pos.x * 2, pos.y);
    const uint inOffset = inPos.x + inPos.y * fbSize.x + field * fbSize.x * fbSize.y;

    // Read and clear internal outputs
    const uint shift0 = min(g_internalSpriteOut[inOffset + 0], 5);
    const uint shift1 = min(g_internalSpriteOut[inOffset + 1], 5);
    if (shift0 == 0 && shift1 == 0) {
        // Nothing written to these pixels
        return;
    }
    g_internalSpriteOut[inOffset + 0] = 0;
    g_internalSpriteOut[inOffset + 1] = 0;

    const uint outOffset = (inPos.x + inPos.y * fbSize.x) * 2 + field * kVDP1FBRAMSize * 2;
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

#elif POLYSPEC_MERGE_MODE == POLYSPEC_SHADING_MODE_OIT
// ----------------------------------------------------------------------------
// OIT (Half-Transparency)

uint HalfTransparentBlend(uint baseColor, uint listHead) {
    // Early exit if nothing was written to the pixel
    if (listHead == 0xFFFFFFFF) {
        return baseColor;
    }

    // Collect fragments
    // TODO: what if the cap is exceeded?
    OITFragment frags[32];
    uint count = 0;
    uint curr = listHead;
    while (curr != 0xFFFFFFFF && count < 32) {
        frags[count++] = g_fragments[curr];
        curr = frags[count - 1].next;
    }

    // Sort by sequence number in descending order (latest to oldest)
    for (uint i = 1; i < count; ++i) {
        OITFragment key = frags[i];
        int j = i - 1;
        while (j >= 0 && BitExtract(frags[j].data, 16, 16) < BitExtract(key.data, 16, 16)) {
            frags[j + 1] = frags[j];
            j--;
        }
        frags[j + 1] = key;
    }

    // Blend colors
    uint4 finalColor = Uint16ToColor555(baseColor);
    for (uint k = 0; k < count; ++k) {
        uint4 fragColor = Uint16ToColor555(frags[k].data);
        if (finalColor.a != 0) {
            finalColor.rgb = (finalColor.rgb + fragColor.rgb) >> 1u;
        } else {
            finalColor = fragColor;
        }
    }

    return Color555ToUint16(finalColor);
}

void Merge8(uint2 pos, uint field) {
    // Half-Transparency does not apply to 8-bit mode.
}

void Merge16(uint2 pos, uint field) {
    const uint2 inPos = uint2(pos.x * 2, pos.y);
    const uint inOffset = inPos.x + inPos.y * fbSize.x + field * fbSize.x * fbSize.y;

    const uint2 heads = uint2(
        g_listHeads[inOffset + 0],
        g_listHeads[inOffset + 1]
    );

    // Early exit if nothing was written to either pixel
    if (all(heads == 0xFFFFFFFF)) {
        return;
    }

    // Clear heads
    g_listHeads[inOffset + 0] = 0xFFFFFFFF;
    g_listHeads[inOffset + 1] = 0xFFFFFFFF;

    // Get base FBRAM value
    const uint fbramAddress = (inPos.x + inPos.y * fbSize.x) * 2 + fbOffset + field * kVDP1FBRAMSize * 2;
    uint fbramValue = g_fbramOut.Load(fbramAddress);

    // Modify
    fbramValue =
        (HalfTransparentBlend(BitExtract(fbramValue, 16, 16), heads[1]) << 16u) |
         HalfTransparentBlend(BitExtract(fbramValue, 0, 16), heads[0]);

    // Write back
    g_fbramOut.Store(fbramAddress, fbramValue);
}

#endif

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(8, 8, 1)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    if (pixel8Bits) {
        Merge8(id.xy, id.z);
    } else {
        Merge16(id.xy, id.z);
    }
}
