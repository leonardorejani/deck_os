package main

import (
	"strings"
	"testing"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"google.golang.org/protobuf/proto"
)

func TestTexto(t *testing.T) {
	s := func(v string) *string { return &v }
	casos := []struct {
		nome string
		m    *waE2E.Message
		want string
		ok   bool
	}{
		{"texto simples", &waE2E.Message{Conversation: s(" oi ")}, "oi", true},
		{"texto longo", &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{Text: s("link aqui")}}, "link aqui", true},
		{"foto sem legenda", &waE2E.Message{ImageMessage: &waE2E.ImageMessage{}}, "Foto", true},
		{"foto com legenda", &waE2E.Message{ImageMessage: &waE2E.ImageMessage{Caption: s("praia")}}, "praia", true},
		{"audio", &waE2E.Message{AudioMessage: &waE2E.AudioMessage{}}, "Áudio", true},
		{"figurinha", &waE2E.Message{StickerMessage: &waE2E.StickerMessage{}}, "Figurinha", true},
		{"reacao nao conta", &waE2E.Message{ReactionMessage: &waE2E.ReactionMessage{}}, "", false},
		{"vazia", &waE2E.Message{}, "", false},
		{"nil", nil, "", false},
	}
	for _, c := range casos {
		got, ok := Texto(c.m)
		if got != c.want || ok != c.ok {
			t.Errorf("%s: veio (%q, %v), esperado (%q, %v)", c.nome, got, ok, c.want, c.ok)
		}
	}
}

func TestAnalisarMidiaEUnica(t *testing.T) {
	foto := &waE2E.Message{ImageMessage: &waE2E.ImageMessage{DirectPath: proto.String("/v/x"), JPEGThumbnail: []byte("miniatura")}}
	c, ok := Analisar(foto, false)
	if !ok || c.Tipo != "foto" || c.Unica || len(c.Ref) == 0 || strings.Contains(string(c.Ref), "miniatura") {
		t.Fatalf("foto comum: %+v", c)
	}
	audio, _ := Analisar(&waE2E.Message{AudioMessage: &waE2E.AudioMessage{DirectPath: proto.String("/v/y")}}, false)
	if audio.Tipo != "audio" || audio.Unica || len(audio.Ref) == 0 {
		t.Fatalf("áudio comum: %+v", audio)
	}
	// Visualização única: balão com o tipo e a marca, e nenhuma referência para baixar o conteúdo.
	vo := true
	casos := map[string]*waE2E.Message{
		"campo viewOnce": {ImageMessage: &waE2E.ImageMessage{ViewOnce: &vo}},
		"embrulho v2":    {ViewOnceMessageV2: &waE2E.FutureProofMessage{Message: &waE2E.Message{ImageMessage: &waE2E.ImageMessage{}}}},
		"embrulho v1":    {ViewOnceMessage: &waE2E.FutureProofMessage{Message: &waE2E.Message{ImageMessage: &waE2E.ImageMessage{}}}},
	}
	for nome, m := range casos {
		c, ok := Analisar(m, false)
		if !ok || !c.Unica || c.Tipo != "foto" || c.Ref != nil {
			t.Errorf("%s: %+v", nome, c)
		}
	}
	a, _ := Analisar(&waE2E.Message{ViewOnceMessageV2: &waE2E.FutureProofMessage{Message: &waE2E.Message{AudioMessage: &waE2E.AudioMessage{}}}}, false)
	if !a.Unica || a.Tipo != "audio" || a.Ref != nil {
		t.Fatalf("áudio único: %+v", a)
	}
}

func TestFormatarNumero(t *testing.T) {
	for em, quer := range map[string]string{"5544984097902": "+55 44 98409-7902", "554433221100": "+55 44 3322-1100", "14155550100": "+14155550100", "": ""} {
		if got := formatarNumero(em); got != quer {
			t.Errorf("%q: veio %q, esperado %q", em, got, quer)
		}
	}
}
