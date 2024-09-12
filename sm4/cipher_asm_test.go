//go:build (amd64 || arm64 || ppc64 || ppc64le) && !purego

package sm4

import (
	"bytes"
	"crypto/cipher"
	"testing"
)

func TestWithoutGFMUL(t *testing.T) {
	key := make([]byte, 16)
	src := make([]byte, 16)
	var dst []byte
	var nonce [12]byte
	var c cipher.Block
	var err error

	if supportSM4 {
		c, err = newCipherNI(key)
	} else if !supportsAES {
		c, err = newCipherGeneric(key)
	} else {
		blocks := 4
		if useAVX2 {
			blocks = 8
		}
		c1 := &sm4CipherAsm{sm4Cipher{}, blocks, blocks * BlockSize}
		expandKeyAsm(&key[0], &ck[0], &c1.enc[0], &c1.dec[0], INST_AES)
		c = c1
	}
	if err != nil {
		t.Fatal(err)
	}

	var sm4gcm cipher.AEAD
	sm4gcm, err = cipher.NewGCM(c)
	if err != nil {
		t.Fatal(err)
	}
	dst = sm4gcm.Seal(nil, nonce[:], src, nil)
	src, err = sm4gcm.Open(nil, nonce[:], dst, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(key, src) {
		t.Errorf("bad encryption")
	}
}
