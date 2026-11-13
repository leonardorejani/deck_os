package main

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"math/rand"
	"testing"
)

func fotoDeTeste(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	r := rand.New(rand.NewSource(1))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.SetRGBA(x, y, color.RGBA{uint8(x/8 + r.Intn(40)), uint8(y/8 + r.Intn(40)), uint8((x + y) / 16), 255})
		}
	}
	var b bytes.Buffer
	_ = jpeg.Encode(&b, img, &jpeg.Options{Quality: 95})
	return b.Bytes()
}

func TestFotoGrandeEReduzidaParaOPainel(t *testing.T) {
	orig := fotoDeTeste(3000, 2000)
	menor := reduzirFoto(orig)
	cfg, _, err := image.DecodeConfig(bytes.NewReader(menor))
	if err != nil || cfg.Width != ladoMaximoFoto || cfg.Height != ladoMaximoFoto*2000/3000 {
		t.Fatalf("tamanho %dx%d (err %v)", cfg.Width, cfg.Height, err)
	}
	t.Logf("foto de %d KB virou %d KB (%.0f%%)", len(orig)>>10, len(menor)>>10, 100*float64(len(menor))/float64(len(orig)))
	if len(menor) >= len(orig)/2 {
		t.Fatalf("deveria cair pelo menos pela metade: %d -> %d", len(orig), len(menor))
	}
}

func TestFotoPequenaEImagemQueNaoAbreSeguemComoChegaram(t *testing.T) {
	peq := fotoDeTeste(200, 150)
	if !bytes.Equal(reduzirFoto(peq), peq) {
		t.Fatal("foto pequena não pode mudar")
	}
	lixo := bytes.Repeat([]byte("x"), 300<<10)
	if !bytes.Equal(reduzirFoto(lixo), lixo) {
		t.Fatal("o que não abre como imagem segue igual")
	}
}
