#ifndef YMIR_INTELLISENSE_COMPAT_HLSLI
#define YMIR_INTELLISENSE_COMPAT_HLSLI

// Defines several compatibility macros for Intellisense to recognize some modern HLSL constructs.

#ifdef __INTELLISENSE__
#define int64_t int
#endif

#endif
