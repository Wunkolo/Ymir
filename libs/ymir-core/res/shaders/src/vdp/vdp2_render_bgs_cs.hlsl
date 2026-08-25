#include "vdp2_render_params_common.hlsli"
#include "vdp2_render_params_layer.hlsli"

#include "vdp2_render_nbg.hlsli"
#include "vdp2_render_rbg.hlsli"

cbuffer CommonRenderParams : register(b0) {
    CommonRenderParams g_renderParams;
}

ByteAddressBuffer vram : register(t1);
Buffer<uint4> cramColor : register(t2);
StructuredBuffer<LayerRenderParams> layerParams : register(t3);

RWTexture2DArray<uint4> bgOut : register(u0);

[numthreads(32, 1, 6)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    const uint2 drawCoord = uint2(id.x, id.y + g_renderParams.startY /*+ ScaleUp(g_renderParams.startY)*/);
    const uint3 outCoord = uint3(drawCoord.x, drawCoord.y /*GetY(drawCoord.y, false)*/, id.z);
    if (id.z <= 3) {
        bgOut[outCoord] = DrawNBG(drawCoord, id.z, vram, cramColor, layerParams);
    } else if (id.z <= 5) {
        bgOut[outCoord] = DrawRBG(drawCoord, id.z - 4, vram, cramColor, layerParams);
    }
}
