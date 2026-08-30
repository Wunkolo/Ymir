#include "vdp2_common_params.hlsli"
#include "vdp2_render_params_rotation.hlsli"

#include "vdp2_defs.hlsli"

#include "util/bit_ops.hlsli"
#include "util/data_ops.hlsli"

cbuffer CommonRenderParamsBuffer : register(b0) {
    CommonRenderParams g_commonParams;
}

StructuredBuffer<RotRegs> rotRegs : register(t1);
StructuredBuffer<RotParamBase> rotParamBases : register(t2);
ByteAddressBuffer vram : register(t3);
ByteAddressBuffer cramCoeff : register(t4);

RWStructuredBuffer<RotParamState> rotParamStatesOut : register(u1);

// ---------------------------------------------------------------------------------------------------------------------
// Parameters

static const bool fbRotEnable = BitTest(g_commonParams.spriteParams, 11);

// ---------------------------------------------------------------------------------------------------------------------
// Table fetching

struct RotTable {
    // Screen start coordinates (signed 13.10 fixed point)
    int Xst, Yst, Zst;

    // Screen vertical coordinate increments (signed 3.10 fixed point)
    int deltaXst, deltaYst;

    // Screen horizontal coordinate increments (signed 3.10 fixed point)
    int deltaX, deltaY;

    // Rotation matrix parameters (signed 4.10 fixed point)
    int A, B, C, D, E, F;

    // Viewpoint coordinates (signed 14-bit integer)
    int Px, Py, Pz;

    // Center point coordinates (signed 14-bit integer)
    int Cx, Cy, Cz;

    // Horizontal shift (signed 14.10 fixed point)
    int Mx, My;

    // Scaling coefficients (signed 8.16 fixed point)
    int kx, ky;

    // Coefficient table parameters
    uint KAst; // Coefficient table start address (unsigned 16.10 fixed point)
    int dKAst; // Coefficient table vertical increment (signed 10.10 fixed point)
    int dKAx; // Coefficient table horizontal increment (signed 10.10 fixed point)
};

struct RotCoefficient {
    int value; // coefficient value, scaled to 16 fractional bits
    uint lineColorData;
    bool transparent;
};

RotTable ReadRotTable(const uint address) {
    RotTable table;

    table.Xst = SignExtend(Read32(vram, address + 0x00) >> 6, 23);
    table.Yst = SignExtend(Read32(vram, address + 0x04) >> 6, 23);
    table.Zst = SignExtend(Read32(vram, address + 0x08) >> 6, 23);

    table.deltaXst = SignExtend(Read32(vram, address + 0x0C) >> 6, 13);
    table.deltaYst = SignExtend(Read32(vram, address + 0x10) >> 6, 13);

    table.deltaX = SignExtend(Read32(vram, address + 0x14) >> 6, 13);
    table.deltaY = SignExtend(Read32(vram, address + 0x18) >> 6, 13);

    table.A = SignExtend(Read32(vram, address + 0x1C) >> 6, 14);
    table.B = SignExtend(Read32(vram, address + 0x20) >> 6, 14);
    table.C = SignExtend(Read32(vram, address + 0x24) >> 6, 14);
    table.D = SignExtend(Read32(vram, address + 0x28) >> 6, 14);
    table.E = SignExtend(Read32(vram, address + 0x2C) >> 6, 14);
    table.F = SignExtend(Read32(vram, address + 0x30) >> 6, 14);

    table.Px = SignExtend(Read16(vram, address + 0x34), 14);
    table.Py = SignExtend(Read16(vram, address + 0x36), 14);
    table.Pz = SignExtend(Read16(vram, address + 0x38), 14);

    table.Cx = SignExtend(Read16(vram, address + 0x3C), 14);
    table.Cy = SignExtend(Read16(vram, address + 0x3E), 14);
    table.Cz = SignExtend(Read16(vram, address + 0x40), 14);

    table.Mx = SignExtend(Read32(vram, address + 0x44) >> 6, 24);
    table.My = SignExtend(Read32(vram, address + 0x48) >> 6, 24);

    table.kx = SignExtend(Read32(vram, address + 0x4C), 24);
    table.ky = SignExtend(Read32(vram, address + 0x50), 24);

    table.KAst = Read32(vram, address + 0x54) >> 6;
    table.dKAst = SignExtend(Read32(vram, address + 0x58) >> 6, 20);
    table.dKAx = SignExtend(Read32(vram, address + 0x5C) >> 6, 20);

    return table;
}

bool CanFetchCoefficient(const RotRegs regs, uint coeffAddress) {
    if (regs.coeffTableCRAM) {
        return true;
    }

    if (!regs.coeffDataPerDot) {
        return true;
    }

    const uint offset = coeffAddress >> 10u;
    const uint address = (offset * 4) >> regs.coeffDataSize;
    const uint bank = BitExtract(address, 17, 2);
    return BitTest(regs.coeffDataAccess, bank);
}

RotCoefficient ReadRotCoefficient(const RotRegs regs, uint coeffAddress) {
    const uint offset = coeffAddress >> 10;
    const bool coeffTableCRAM = regs.coeffTableCRAM;
    const bool coeffDataSize = regs.coeffDataSize;
    const uint coeffDataMode = regs.coeffDataMode;

    RotCoefficient coeff;

    // Force coefficient to 0 if it cannot be read in per-dot mode
    if (!CanFetchCoefficient(regs, coeffAddress)) {
        coeff.value = 0;
        coeff.lineColorData = 0;
        coeff.transparent = true;
        return coeff;
    }

    if (coeffDataSize) {
        // One-word coefficient data
        const uint address = offset * 2;
        const uint data = coeffTableCRAM ? Read16(cramCoeff, address) : Read16(vram, address);
        coeff.value = SignExtend(data, 15);
        coeff.lineColorData = 0;
        coeff.transparent = BitTest(data, 15);

        if (coeffDataMode == kCoeffDataModeViewpointX) {
            coeff.value <<= 14;
        } else {
            coeff.value <<= 6;
        }
    } else {
        // Two-word coefficient data
        const uint address = offset * 4;
        const uint data = coeffTableCRAM ? Read32(cramCoeff, address) : Read32(vram, address);
        coeff.value = SignExtend(data, 24);
        coeff.lineColorData = BitExtract(data, 24, 7);
        coeff.transparent = BitTest(data, 31);

        if (coeffDataMode == kCoeffDataModeViewpointX) {
            coeff.value <<= 8;
        }
    }

    return coeff;
}

// ---------------------------------------------------------------------------------------------------------------------
// Calculation

RotParamState CalcRotation(uint2 pos, uint index) {
    const RotParamBase base = rotParamBases[index * kMaxNormalResV + pos.y + g_commonParams.startY];
    const RotRegs regs = rotRegs[index];

    const RotTable t = ReadRotTable(base.tableAddress);

    int Tx, Ty, Tz;

    // Common terms for Xsp and Ysp (14.10)
    // 10 - 0 = 10 frac bits
    // 23 - 14 = 23 total bits
    // expand to 10 frac bits
    // 10 - 10 = 10 frac bits
    // 23 - 24 = 24 total bits
    const int Xst = base.Xst;
    const int Yst = base.Yst;
    const int Zst = t.Zst;
    Tx = Xst - (t.Px << 10);
    Ty = Yst - (t.Py << 10);
    Tz = Zst - (t.Pz << 10);

    // Transformed starting screen coordinates (18.10)
    // 10*(10-10) + 10*(10-10) + 10*(10-10) = 20 frac bits
    // 14*(23-24) + 14*(23-24) + 14*(23-24) = 38 total bits
    // reduce to 10 frac bits
    const int Xsp = int((int64_t(t.A) * int64_t(Tx) + int64_t(t.B) * int64_t(Ty) + int64_t(t.C) * int64_t(Tz)) >> 10);
    const int Ysp = int((int64_t(t.D) * int64_t(Tx) + int64_t(t.E) * int64_t(Ty) + int64_t(t.F) * int64_t(Tz)) >> 10);

    // Transformed view coordinates (18.10)
    // 10*(0-0) + 10*(0-0) + 10*(0-0) + 10 + 10 = 10+10+10 + 10+10 = 10 frac bits
    // 14*(14-14) + 14*(14-14) + 14*(14-14) + 24 + 24 = 28+28+28 + 24+24 = 28 total bits
    Tx = t.Px - t.Cx;
    Ty = t.Py - t.Cy;
    Tz = t.Pz - t.Cz;
    int /***/ Xp = t.A * Tx + t.B * Ty + t.C * Tz + (t.Cx << 10) + t.Mx;
    const int Yp = t.D * Tx + t.E * Ty + t.F * Tz + (t.Cy << 10) + t.My;

    // Screen coordinate increments per Hcnt (7.10)
    // 10*10 + 10*10 = 20 + 20 = 20 frac bits
    // 14*13 + 14*13 = 27 + 27 = 27 total bits
    // reduce to 10 frac bits
    const int scrXIncH = (t.A * t.deltaX + t.B * t.deltaY) >> 10;
    const int scrYIncH = (t.D * t.deltaX + t.E * t.deltaY) >> 10;

    int kx = t.kx;
    int ky = t.ky;

    RotCoefficient coeff;
    if (regs.coeffTableEnable) {
        // Current coefficient address (16.10)
        const uint KAxofs = regs.coeffDataPerDot ? pos.x * t.dKAx : 0;
        const uint KA = base.KA + KAxofs;

        // Read and apply rotation coefficient
        coeff = ReadRotCoefficient(regs, KA);

        switch (regs.coeffDataMode) {
            case kCoeffDataModeScaleCoeffXY:
                kx = ky = coeff.value;
                break;
            case kCoeffDataModeScaleCoeffX:
                kx = coeff.value;
                break;
            case kCoeffDataModeScaleCoeffY:
                ky = coeff.value;
                break;
            case kCoeffDataModeViewpointX:
                Xp = coeff.value << 2;
                break;
        }
    } else {
        coeff.value = 0;
        coeff.lineColorData = 0;
        coeff.transparent = true;
    }

    RotParamState result;

    // Current screen coordinates (18.10)
    const int scrX = Xsp + pos.x * scrXIncH;
    const int scrY = Ysp + pos.x * scrYIncH;

    // Resulting screen coordinates (26.0)
    // (16*10) + 10 = 26 + 10 frac bits
    // (24*28) + 28 = 52 + 28 total bits
    // reduce 26 to 10 frac bits
    // = 10 + 10 = 10 frac bits
    // = 36 + 28 = 36 total bits
    // remove frac bits from result = 26 total bits
    result.screenCoords = int2(
        (((int64_t(kx) * scrX) >> 16) + Xp) >> 10,
        (((int64_t(ky) * scrY) >> 16) + Yp) >> 10
    );

    if (fbRotEnable && index == 0) {
        // Current sprite coordinates (13.10)
        // 10 + 0*10 + 0*10 = 10 + 10 + 10 = 10 frac bits
        // 23 + 10*13 + 9*13 = 23 + 23 + 22 = 23 total bits
        const int sprX = t.Xst + pos.y * t.deltaXst + pos.x * t.deltaX;
        const int sprY = t.Yst + pos.y * t.deltaYst + pos.x * t.deltaY;

        // Pack resulting sprite coordinates (13.0)
        result.spriteCoords = ((sprX >> 10) & 0xFFFF) | ((sprY >> 10) << 16);
    } else {
        result.spriteCoords = 0;
    }

    // Pack coefficient data
    result.coeffData = coeff.lineColorData;
    if (coeff.transparent) {
        result.coeffData |= 0x80;
    }

    return result;
}

// ---------------------------------------------------------------------------------------------------------------------
// Entrypoint

[numthreads(32, 1, 2)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    const uint outIndex = id.x + (id.y + g_commonParams.startY) * kRotParamLinePitch + id.z * kRotParamEntryStride;
    rotParamStatesOut[outIndex] = CalcRotation(id.xy, id.z);
}
