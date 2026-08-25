#ifndef YMIR_VDP_VDP2_RBG_HLSLI
#define YMIR_VDP_VDP2_RBG_HLSLI

#include "vdp2_render_params_layer.hlsli"
#include "vdp2_defs.hlsli"
#include "vdp2_utils.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

uint4 DrawRBG(uint2 pos, // pixel coordinates
              uint index, // RBG index (0 to 1)
              ByteAddressBuffer vram,
              Buffer<uint4> cramColor,
              StructuredBuffer<LayerRenderParams> layerParams) {
    RBGParams params = layerParams[0].rbg[index];
    if (!params.base.enabled) {
        return kTransparentPixel;
    }
    return uint4(pos.x, pos.y, index, 1);
}

#endif
