#ifndef YMIR_VDP_VDP2_NBG_HLSLI
#define YMIR_VDP_VDP2_NBG_HLSLI

#include "vdp2_render_params_layer.hlsli"
#include "vdp2_defs.hlsli"
#include "vdp2_utils.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

uint4 DrawNBG(uint2 pos, // pixel coordinates
              uint index, // NBG index (0 to 3)
              ByteAddressBuffer vram,
              Buffer<uint4> cramColor,
              StructuredBuffer<LayerRenderParams> layerParams) {
    NBGParams params = layerParams[0].nbg[index];
    if (!params.base.enabled) {
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

#endif
