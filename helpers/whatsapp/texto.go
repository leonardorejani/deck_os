package main

import (
	"strings"

	"go.mau.fi/whatsmeow/proto/waE2E"
)

// Texto devolve o que a mensagem mostra na lista. Mídia sem legenda aparece pelo tipo, com os mesmos
// rótulos da leitura do banco do app. ok=false para o que não é mensagem de gente (reação, apagar,
// protocolo): essas não contam como não lida.
func Texto(m *waE2E.Message) (texto string, ok bool) {
	if m == nil {
		return "", false
	}
	if s := strings.TrimSpace(m.GetConversation()); s != "" {
		return s, true
	}
	if e := m.GetExtendedTextMessage(); e != nil {
		if s := strings.TrimSpace(e.GetText()); s != "" {
			return s, true
		}
	}
	legenda := func(s string, rotulo string) (string, bool) {
		if s = strings.TrimSpace(s); s != "" {
			return s, true
		}
		return rotulo, true
	}
	switch {
	case m.GetImageMessage() != nil:
		return legenda(m.GetImageMessage().GetCaption(), "Foto")
	case m.GetVideoMessage() != nil:
		if m.GetVideoMessage().GetGifPlayback() {
			return legenda(m.GetVideoMessage().GetCaption(), "GIF")
		}
		return legenda(m.GetVideoMessage().GetCaption(), "Vídeo")
	case m.GetPtvMessage() != nil:
		return "Vídeo", true
	case m.GetAudioMessage() != nil:
		return "Áudio", true
	case m.GetDocumentMessage() != nil:
		return legenda(m.GetDocumentMessage().GetCaption(), "Documento")
	case m.GetStickerMessage() != nil:
		return "Figurinha", true
	case m.GetContactMessage() != nil, m.GetContactsArrayMessage() != nil:
		return "Contato", true
	case m.GetLocationMessage() != nil, m.GetLiveLocationMessage() != nil:
		return "Localização", true
	case m.GetPollCreationMessage() != nil:
		return "Enquete", true
	}
	return "", false
}
