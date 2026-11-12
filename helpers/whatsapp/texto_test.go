package main

import (
	"testing"

	"go.mau.fi/whatsmeow/proto/waE2E"
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
