#include "vdp2_common_params.hlsli"
#include "vdp2_compose_params.hlsli"

#include "vdp2_defs.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

cbuffer CommonRenderParams : register(b0) {
    CommonRenderParams g_commonParams;
}

StructuredBuffer<ComposeParams> composeParams : register(t1);
Texture2DArray<uint4> layerIn : register(t2);
StructuredBuffer<uint4> lineColorIn : register(t3);
Texture2DArray<uint4> rbgLineColorIn : register(t4);
// Texture2D<uint> spriteAttrsIn : register(t5);
// Texture2D<uint4> colorCalcWindowIn : register(t6);

RWTexture2D<float4> textureOut : register(u0);

// ---------------------------------------------------------------------------------------------------------------------
// Parameters

static const uint interlaceMode = BitExtract(g_commonParams.displayParams, 2, 2);
static const uint oddField = BitExtract(g_commonParams.displayParams, 4, 1);
static const bool exclusiveMonitor = BitTest(g_commonParams.displayParams, 5);

static const bool deinterlace = BitTest(g_commonParams.enhancements, 0);
static const bool transparentMeshes = BitTest(g_commonParams.enhancements, 1);

// ---------------------------------------------------------------------------------------------------------------------
// Utilities

uint GetOutputY(uint y) {
    if (!deinterlace && interlaceMode >= kInterlaceModeSingleDensity && !exclusiveMonitor) {
        return (y << 1) | oddField;
    } else {
        return y;
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Compositor

uint3 Compose(uint2 basePos) {
    return layerIn[uint3(basePos.xy, 0)].rgb;
}

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(32, 1, 1)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    const uint2 drawCoord = uint2(id.x, id.y + g_commonParams.startY);
    const uint2 outCoord = uint2(drawCoord.x, GetOutputY(drawCoord.y));
    const uint3 outColor = Compose(drawCoord);
    textureOut[outCoord] = float4(outColor / 255.0, 1.0f);
}
