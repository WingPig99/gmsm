//go:build amd64 && !purego
// +build amd64,!purego

#include "textflag.h"

#define x X0
#define y X1
#define t0 X2
#define t1 X3
#define t2 X4
#define t3 X5

#define XTMP6 X6
#define IV X8

#include "aesni_macros_amd64.s"

// func encryptBlocksChain(xk *uint32, dst, src []byte, iv *byte)
TEXT ·encryptBlocksChain(SB),NOSPLIT,$0
#define ctx BX
#define ptx DX
#define ptxLen DI

	MOVQ xk+0(FP), AX
	MOVQ dst+8(FP), ctx
	MOVQ src+32(FP), ptx
	MOVQ src_len+40(FP), ptxLen
	MOVQ iv+56(FP), SI

	MOVUPS (SI), IV

loopSrc:
		CMPQ ptxLen, $16
		JB done_sm4
		SUBQ $16, ptxLen

		MOVOU (ptx), t0
		PXOR IV, t0

		PSHUFB flip_mask<>(SB), t0
		PSHUFD $1, t0, t1
		PSHUFD $2, t0, t2
		PSHUFD $3, t0, t3

		XORL CX, CX

loopRound:
			SM4_SINGLE_ROUND(0, AX, CX, x, y, XTMP6, t0, t1, t2, t3)
			SM4_SINGLE_ROUND(1, AX, CX, x, y, XTMP6, t1, t2, t3, t0)
			SM4_SINGLE_ROUND(2, AX, CX, x, y, XTMP6, t2, t3, t0, t1)
			SM4_SINGLE_ROUND(3, AX, CX, x, y, XTMP6, t3, t0, t1, t2)

			ADDL $16, CX
			CMPL CX, $4*32
			JB loopRound

		PALIGNR $4, t3, t3
		PALIGNR $4, t3, t2
		PALIGNR $4, t2, t1
		PALIGNR $4, t1, t0
		PSHUFB flip_mask<>(SB), t0

		MOVOU t0, IV
		MOVOU t0, (ctx)

		LEAQ 16(ptx), ptx
		LEAQ 16(ctx), ctx
	
		JMP loopSrc

done_sm4:
	MOVUPS IV, (SI)
	RET

#undef ctx
#undef ptx
#undef ptxLen

#define XDWTMP0 Y0
#define XDWTMP1 Y1
#define XDWTMP2 Y2

#define XDWORD0 Y4
#define XDWORD1 Y5
#define XDWORD2 Y6
#define XDWORD3 Y7

#define XWTMP0 X0
#define XWTMP1 X1
#define XWTMP2 X2

#define XWORD0 X4
#define XWORD1 X5
#define XWORD2 X6
#define XWORD3 X7

#define NIBBLE_MASK Y3
#define X_NIBBLE_MASK X3

#define BYTE_FLIP_MASK 	Y13 // mask to convert LE -> BE
#define X_BYTE_FLIP_MASK 	X13 // mask to convert LE -> BE

#define XDWORD Y8
#define YDWORD Y9

#define XWORD X8
#define YWORD X9

// SM4 round function, AVX2 version, handle 256 bits
// t0 ^= tao_l1(t1^t2^t3^xk)
// parameters:
// - index: round key index immediate number
// - x: 256 bits temp register
// - y: 256 bits temp register
// - t0: 256 bits register for data as result
// - t1: 256 bits register for data
// - t2: 256 bits register for data
// - t3: 256 bits register for data
#define AVX2_SM4_ROUND(index, x, y, t0, t1, t2, t3)                                                    \
	VPBROADCASTD (index * 4)(AX)(CX*1), x;                                                               \
	VPXOR t1, x, x;                                                                                      \
	VPXOR t2, x, x;                                                                                      \
	VPXOR t3, x, x;                                                                                      \
	AVX2_SM4_TAO_L1(x, y, XDWTMP0, XWORD, YWORD, X_NIBBLE_MASK, NIBBLE_MASK);                            \
	VPXOR x, t0, t0

// SM4 round function, AVX version, handle 128 bits
// t0 ^= tao_l1(t1^t2^t3^xk)
// parameters:
// - index: round key index immediate number
// - x: 128 bits temp register
// - y: 128 bits temp register
// - t0: 128 bits register for data as result
// - t1: 128 bits register for data
// - t2: 128 bits register for data
// - t3: 128 bits register for data
#define AVX_SM4_ROUND(index, x, y, t0, t1, t2, t3)  \ 
	VPBROADCASTD (index * 4)(AX)(CX*1), x;             \
	VPXOR t1, x, x;                                    \
	VPXOR t2, x, x;                                    \
	VPXOR t3, x, x;                                    \
	AVX_SM4_TAO_L1(x, y, X_NIBBLE_MASK, XWTMP0);       \  
	VPXOR x, t0, t0

// func decryptBlocksChain(xk *uint32, dst, src []byte, iv *byte)
TEXT ·decryptBlocksChain(SB),NOSPLIT,$0
	MOVQ xk+0(FP), AX
	MOVQ dst+8(FP), BX
	MOVQ src+32(FP), DX
	MOVQ iv+56(FP), SI

	CMPB ·useAVX2(SB), $1
	JE   avx2

	CMPB ·useAVX(SB), $1
	JE   avx

non_avx2_start:
	MOVOU 0(DX), t0
	MOVOU 16(DX), t1
	MOVOU 32(DX), t2
	MOVOU 48(DX), t3
	PSHUFB flip_mask<>(SB), t0
	PSHUFB flip_mask<>(SB), t1
	PSHUFB flip_mask<>(SB), t2
	PSHUFB flip_mask<>(SB), t3
	SSE_TRANSPOSE_MATRIX(t0, t1, t2, t3, x, y)

	XORL CX, CX

loop:
		SM4_ROUND(0, AX, CX, x, y, XTMP6, t0, t1, t2, t3)
		SM4_ROUND(1, AX, CX, x, y, XTMP6, t1, t2, t3, t0)
		SM4_ROUND(2, AX, CX, x, y, XTMP6, t2, t3, t0, t1)
		SM4_ROUND(3, AX, CX, x, y, XTMP6, t3, t0, t1, t2)

		ADDL $16, CX
		CMPL CX, $4*32
		JB loop

	SSE_TRANSPOSE_MATRIX(t0, t1, t2, t3, x, y);  
	PSHUFB bswap_mask<>(SB), t3
	PSHUFB bswap_mask<>(SB), t2
	PSHUFB bswap_mask<>(SB), t1
	PSHUFB bswap_mask<>(SB), t0

	PXOR 0(SI), t0
	PXOR 16(SI), t1
	PXOR 32(SI), t2
	PXOR 48(SI), t3

	MOVUPS t0, 0(BX)
	MOVUPS t1, 16(BX)
	MOVUPS t2, 32(BX)
	MOVUPS t3, 48(BX)

done_sm4:
	RET

avx:
	VMOVDQU 0(DX), XWORD0
	VMOVDQU 16(DX), XWORD1
	VMOVDQU 32(DX), XWORD2
	VMOVDQU 48(DX), XWORD3

	VMOVDQU nibble_mask<>(SB), X_NIBBLE_MASK
	VMOVDQU flip_mask<>(SB), X_BYTE_FLIP_MASK

	VPSHUFB X_BYTE_FLIP_MASK, XWORD0, XWORD0
	VPSHUFB X_BYTE_FLIP_MASK, XWORD1, XWORD1
	VPSHUFB X_BYTE_FLIP_MASK, XWORD2, XWORD2
	VPSHUFB X_BYTE_FLIP_MASK, XWORD3, XWORD3

	// Transpose matrix 4 x 4 32bits word
	TRANSPOSE_MATRIX(XWORD0, XWORD1, XWORD2, XWORD3, XWTMP1, XWTMP2)

	XORL CX, CX

avx_loop:
		AVX_SM4_ROUND(0, XWORD, YWORD, XWORD0, XWORD1, XWORD2, XWORD3)
		AVX_SM4_ROUND(1, XWORD, YWORD, XWORD1, XWORD2, XWORD3, XWORD0)
		AVX_SM4_ROUND(2, XWORD, YWORD, XWORD2, XWORD3, XWORD0, XWORD1)
		AVX_SM4_ROUND(3, XWORD, YWORD, XWORD3, XWORD0, XWORD1, XWORD2)

		ADDL $16, CX
		CMPL CX, $4*32
		JB avx_loop

	// Transpose matrix 4 x 4 32bits word
	TRANSPOSE_MATRIX(XWORD0, XWORD1, XWORD2, XWORD3, XWTMP1, XWTMP2)

	VMOVDQU bswap_mask<>(SB), X_BYTE_FLIP_MASK
	VPSHUFB X_BYTE_FLIP_MASK, XWORD0, XWORD0
	VPSHUFB X_BYTE_FLIP_MASK, XWORD1, XWORD1
	VPSHUFB X_BYTE_FLIP_MASK, XWORD2, XWORD2
	VPSHUFB X_BYTE_FLIP_MASK, XWORD3, XWORD3

	VPXOR 0(SI), XWORD0, XWORD0
	VPXOR 16(SI), XWORD1, XWORD1
	VPXOR 32(SI), XWORD2, XWORD2
	VPXOR 48(SI), XWORD3, XWORD3

	VMOVDQU XWORD0, 0(BX)
	VMOVDQU XWORD1, 16(BX)
	VMOVDQU XWORD2, 32(BX)
	VMOVDQU XWORD3, 48(BX)

	RET

avx2:
	VBROADCASTI128 nibble_mask<>(SB), NIBBLE_MASK

avx2_8blocks:
	VMOVDQU 0(DX), XDWORD0
	VMOVDQU 32(DX), XDWORD1
	VMOVDQU 64(DX), XDWORD2
	VMOVDQU 96(DX), XDWORD3
	VBROADCASTI128 flip_mask<>(SB), BYTE_FLIP_MASK

	// Apply Byte Flip Mask: LE -> BE
	VPSHUFB BYTE_FLIP_MASK, XDWORD0, XDWORD0
	VPSHUFB BYTE_FLIP_MASK, XDWORD1, XDWORD1
	VPSHUFB BYTE_FLIP_MASK, XDWORD2, XDWORD2
	VPSHUFB BYTE_FLIP_MASK, XDWORD3, XDWORD3

	// Transpose matrix 4 x 4 32bits word
	TRANSPOSE_MATRIX(XDWORD0, XDWORD1, XDWORD2, XDWORD3, XDWTMP1, XDWTMP2)

	XORL CX, CX

avx2_loop:
		AVX2_SM4_ROUND(0, XDWORD, YDWORD, XDWORD0, XDWORD1, XDWORD2, XDWORD3)
		AVX2_SM4_ROUND(1, XDWORD, YDWORD, XDWORD1, XDWORD2, XDWORD3, XDWORD0)
		AVX2_SM4_ROUND(2, XDWORD, YDWORD, XDWORD2, XDWORD3, XDWORD0, XDWORD1)
		AVX2_SM4_ROUND(3, XDWORD, YDWORD, XDWORD3, XDWORD0, XDWORD1, XDWORD2)

		ADDL $16, CX
		CMPL CX, $4*32
		JB avx2_loop

	// Transpose matrix 4 x 4 32bits word
	TRANSPOSE_MATRIX(XDWORD0, XDWORD1, XDWORD2, XDWORD3, XDWTMP1, XDWTMP2)

	VBROADCASTI128 bswap_mask<>(SB), BYTE_FLIP_MASK
	VPSHUFB BYTE_FLIP_MASK, XDWORD0, XDWORD0
	VPSHUFB BYTE_FLIP_MASK, XDWORD1, XDWORD1
	VPSHUFB BYTE_FLIP_MASK, XDWORD2, XDWORD2
	VPSHUFB BYTE_FLIP_MASK, XDWORD3, XDWORD3

	VPXOR 0(SI), XDWORD0, XDWORD0
	VPXOR 32(SI), XDWORD1, XDWORD1
	VPXOR 64(SI), XDWORD2, XDWORD2
	VPXOR 96(SI), XDWORD3, XDWORD3

	VMOVDQU XDWORD0, 0(BX)
	VMOVDQU XDWORD1, 32(BX)
	VMOVDQU XDWORD2, 64(BX)
	VMOVDQU XDWORD3, 96(BX)


avx2_sm4_done:
	VZEROUPPER
	RET
