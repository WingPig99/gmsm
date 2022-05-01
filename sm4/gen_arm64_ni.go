// Not used yet!!!
// go run gen_arm64_ni.go

//go:build ignore
// +build ignore

package main

import (
	"bytes"
	"fmt"
	"log"
	"math/bits"
	"os"
)

//SM4E <Vd>.4S, <Vn>.4S
func sm4e(Vd, Vn byte) uint32 {
	inst := uint32(0xcec08400) | uint32(Vd&0x1f) | uint32(Vn&0x1f)<<5
	return bits.ReverseBytes32(inst)
}

//SM4EKEY <Vd>.4S, <Vn>.4S, <Vm>.4S
func sm4ekey(Vd, Vn, Vm byte) uint32 {
	inst := uint32(0xce60c800) | uint32(Vd&0x1f) | uint32(Vn&0x1f)<<5 | (uint32(Vm&0x1f) << 16)
	return bits.ReverseBytes32(inst)
}

func sm4ekeyRound(buf *bytes.Buffer, d, n, m byte) {
	fmt.Fprintf(buf, "\tWORD $0x%08x          //SM4EKEY V%d.4S, V%d.4S, V%d.4S\n", sm4ekey(d, n, m), d, n, m)
}

func sm4eRound(buf *bytes.Buffer, d, n byte) {
	fmt.Fprintf(buf, "\tWORD $0x%08x          //SM4E V%d.4S, V%d.4S\n", sm4e(d, n), d, n)
}

func main() {
	buf := new(bytes.Buffer)
	fmt.Fprint(buf, `
// Generated by gen_arm64_ni.go. DO NOT EDIT.

#include "textflag.h"

// func expandKeySM4E(key *byte, fk, ck, enc *uint32)
TEXT ·expandKeySM4E(SB),NOSPLIT,$0
	MOVD key+0(FP), R8
	MOVD fk+8(FP), R9
	MOVD ck+16(FP), R10
	MOVD enc+24(FP), R11

	VLD1 (R8), [V9.B16]
	VREV32 V9.B16, V9.B16
	VLD1 (R9), [V8.S4]
	VEOR V9, V8, V9
	VLD1.P	64(R10), [V0.S4, V1.S4, V2.S4, V3.S4]
`[1:])

	sm4ekeyRound(buf, 8, 9, 0)
	sm4ekeyRound(buf, 9, 8, 1)
	fmt.Fprintf(buf, "\tVST1.P	[V8.S4, V9.S4], 32(R11)\n")
	sm4ekeyRound(buf, 8, 9, 2)
	sm4ekeyRound(buf, 9, 8, 3)
	fmt.Fprintf(buf, "\tVST1.P	[V8.S4, V9.S4], 32(R11)\n")
	fmt.Fprintf(buf, "\tVLD1.P	64(R10), [V0.S4, V1.S4, V2.S4, V3.S4]\n")
	sm4ekeyRound(buf, 8, 9, 0)
	sm4ekeyRound(buf, 9, 8, 1)
	fmt.Fprintf(buf, "\tVST1.P	[V8.S4, V9.S4], 32(R11)\n")
	sm4ekeyRound(buf, 8, 9, 2)
	sm4ekeyRound(buf, 9, 8, 3)
	fmt.Fprintf(buf, `
	VST1.P	[V8.S4, V9.S4], 32(R11)
	RET
`[1:])
	fmt.Fprint(buf, `

// func encryptBlockSM4E(xk *uint32, dst, src *byte)
TEXT ·encryptBlockSM4E(SB),NOSPLIT,$0
	MOVD xk+0(FP), R8
	MOVD dst+8(FP), R9
	MOVD src+16(FP), R10

	VLD1 (R10), [V8.B16]
	VREV32 V8.B16, V8.B16
	VLD1.P	64(R8), [V0.S4, V1.S4, V2.S4, V3.S4]
`[1:])
	sm4eRound(buf, 8, 0)
	sm4eRound(buf, 8, 1)
	sm4eRound(buf, 8, 2)
	sm4eRound(buf, 8, 3)
	fmt.Fprintf(buf, "\tVLD1.P	64(R8), [V0.S4, V1.S4, V2.S4, V3.S4]\n")
	sm4eRound(buf, 8, 0)
	sm4eRound(buf, 8, 1)
	sm4eRound(buf, 8, 2)
	sm4eRound(buf, 8, 3)
	fmt.Fprintf(buf, `
	VREV32 V8.B16, V8.B16
	VST1	[V8.B16], (R9)
	RET
`[1:])

	fmt.Fprint(buf, `

// func encryptBlocksSM4E(xk *uint32, dst, src *byte)
TEXT ·encryptBlocksSM4E(SB),NOSPLIT,$0
	MOVD xk+0(FP), R8
	MOVD dst+8(FP), R9
	MOVD src+16(FP), R10

	VLD1.P	64(R8), [V0.S4, V1.S4, V2.S4, V3.S4]
	VLD1.P	64(R8), [V4.S4, V5.S4, V6.S4, V7.S4]

`[1:])
	for i := 0; i < 4; i++ {
		fmt.Fprintf(buf, "\tVLD1.P 16(R10), [V8.B16]\n")
		fmt.Fprintf(buf, "\tVREV32 V8.B16, V8.B16\n")
		sm4eRound(buf, 8, 0)
		sm4eRound(buf, 8, 1)
		sm4eRound(buf, 8, 2)
		sm4eRound(buf, 8, 3)
		sm4eRound(buf, 8, 4)
		sm4eRound(buf, 8, 5)
		sm4eRound(buf, 8, 6)
		sm4eRound(buf, 8, 7)
		fmt.Fprintf(buf, "\tVREV32 V8.B16, V8.B16\n")
		fmt.Fprintf(buf, "\tVST1.P	[V8.B16], 16(R9)\n\n")
	}
	fmt.Fprintf(buf, `
	RET
`[1:])

	src := buf.Bytes()
	// fmt.Println(string(src))
	err := os.WriteFile("sm4e_arm64.s", src, 0644)
	if err != nil {
		log.Fatal(err)
	}
}