package main

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
)

// A foto de uma mensagem chega do WhatsApp com 1 a 3 MB, e o iPhone a recebe em base64 pelo cabo, pelo Wi-Fi ou pelo
// Bluetooth. A tela do painel não mostra mais que isso, então a cópia que o Deck guarda e entrega é reduzida
// (lado maior de ladoMaximoFoto, JPEG com qualidade 80). Se a imagem não abre (WebP, por exemplo) ou já é pequena,
// segue a original.
const (
	ladoMaximoFoto    = 1280
	qualidadeDaFoto   = 80
	tamanhoSemReduzir = 150 << 10
)

func reduzirFoto(dados []byte) []byte {
	if len(dados) <= tamanhoSemReduzir {
		return dados
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(dados))
	if err != nil || (cfg.Width <= ladoMaximoFoto && cfg.Height <= ladoMaximoFoto && len(dados) <= 600<<10) {
		return dados
	}
	img, _, err := image.Decode(bytes.NewReader(dados))
	if err != nil {
		return dados
	}
	menor := reduzirImagem(img, ladoMaximoFoto)
	var saida bytes.Buffer
	if jpeg.Encode(&saida, menor, &jpeg.Options{Quality: qualidadeDaFoto}) != nil || saida.Len() >= len(dados) {
		return dados
	}
	return saida.Bytes()
}

// reduzirImagem faz a média da área de cada pixel novo (sem dependência externa). Não amplia.
func reduzirImagem(src image.Image, lado int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= lado && h <= lado {
		return src
	}
	nw, nh := lado, lado*h/w
	if h > w {
		nw, nh = lado*w/h, lado
	}
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	for y := 0; y < nh; y++ {
		y0, y1 := b.Min.Y+y*h/nh, b.Min.Y+(y+1)*h/nh
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for x := 0; x < nw; x++ {
			x0, x1 := b.Min.X+x*w/nw, b.Min.X+(x+1)*w/nw
			if x1 <= x0 {
				x1 = x0 + 1
			}
			var r, g, bl, n uint64
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					cr, cg, cb, _ := src.At(xx, yy).RGBA()
					r, g, bl, n = r+uint64(cr), g+uint64(cg), bl+uint64(cb), n+1
				}
			}
			dst.SetRGBA(x, y, color.RGBA{uint8(r / n >> 8), uint8(g / n >> 8), uint8(bl / n >> 8), 255})
		}
	}
	return dst
}
