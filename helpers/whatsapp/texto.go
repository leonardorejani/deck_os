package main

import (
	"fmt"
	"strings"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"google.golang.org/protobuf/proto"
)

// Conteudo é o que a mensagem mostra na lista do Deck.
type Conteudo struct {
	Texto string
	// Tipo: "foto", "audio" ou "video" quando a mensagem é mídia. Vazio é texto ou outro tipo.
	Tipo string
	// Unica: visualização única. O Deck mostra só o balão com o ícone, nunca o conteúdo.
	Unica bool
	// Ref: a mídia (sem miniatura) para baixar sob demanda. Só foto e áudio, e nunca de visualização única.
	Ref []byte
}

// Texto devolve o que a mensagem mostra na lista. Mídia sem legenda aparece pelo tipo, com os mesmos
// rótulos da leitura do banco do app. ok=false para o que não é mensagem de gente (reação, apagar,
// protocolo): essas não contam como não lida.
func Texto(m *waE2E.Message) (texto string, ok bool) {
	c, ok := Analisar(m, false)
	return c.Texto, ok
}

// Analisar lê a mensagem. `unica` vale quando ela já veio de dentro de uma visualização única.
func Analisar(m *waE2E.Message, unica bool) (Conteudo, bool) {
	if m == nil {
		return Conteudo{}, false
	}
	// O embrulho da visualização única nasce no histórico (a whatsmeow já desembrulha as mensagens ao vivo).
	for _, v := range []*waE2E.FutureProofMessage{m.GetViewOnceMessage(), m.GetViewOnceMessageV2(), m.GetViewOnceMessageV2Extension()} {
		if v != nil && v.GetMessage() != nil {
			return Analisar(v.GetMessage(), true)
		}
	}
	if s := strings.TrimSpace(m.GetConversation()); s != "" {
		return Conteudo{Texto: s}, true
	}
	if e := m.GetExtendedTextMessage(); e != nil {
		if s := strings.TrimSpace(e.GetText()); s != "" {
			return Conteudo{Texto: s}, true
		}
	}
	legenda := func(s string, rotulo string) string {
		if s = strings.TrimSpace(s); s != "" {
			return s
		}
		return rotulo
	}
	switch {
	case m.GetImageMessage() != nil:
		img := m.GetImageMessage()
		if unica || img.GetViewOnce() {
			return Conteudo{Texto: "Foto única", Tipo: "foto", Unica: true}, true
		}
		c := proto.Clone(img).(*waE2E.ImageMessage)
		c.JPEGThumbnail, c.ContextInfo = nil, nil
		ref, _ := proto.Marshal(c)
		return Conteudo{Texto: legenda(img.GetCaption(), "Foto"), Tipo: "foto", Ref: ref}, true
	case m.GetVideoMessage() != nil:
		v := m.GetVideoMessage()
		if unica || v.GetViewOnce() {
			return Conteudo{Texto: "Vídeo único", Tipo: "video", Unica: true}, true
		}
		if v.GetGifPlayback() {
			return Conteudo{Texto: legenda(v.GetCaption(), "GIF"), Tipo: "video"}, true
		}
		return Conteudo{Texto: legenda(v.GetCaption(), "Vídeo"), Tipo: "video"}, true
	case m.GetPtvMessage() != nil:
		return Conteudo{Texto: "Vídeo", Tipo: "video"}, true
	case m.GetAudioMessage() != nil:
		a := m.GetAudioMessage()
		if unica || a.GetViewOnce() {
			return Conteudo{Texto: "Áudio único", Tipo: "audio", Unica: true}, true
		}
		c := proto.Clone(a).(*waE2E.AudioMessage)
		c.Waveform, c.ContextInfo = nil, nil
		ref, _ := proto.Marshal(c)
		return Conteudo{Texto: "Áudio", Tipo: "audio", Ref: ref}, true
	case m.GetDocumentMessage() != nil:
		return Conteudo{Texto: legenda(m.GetDocumentMessage().GetCaption(), "Documento")}, true
	case m.GetStickerMessage() != nil:
		return Conteudo{Texto: "Figurinha"}, true
	case m.GetContactMessage() != nil, m.GetContactsArrayMessage() != nil:
		return Conteudo{Texto: "Contato"}, true
	case m.GetLocationMessage() != nil, m.GetLiveLocationMessage() != nil:
		return Conteudo{Texto: "Localização"}, true
	case m.GetPollCreationMessage() != nil:
		return Conteudo{Texto: "Enquete"}, true
	}
	return Conteudo{}, false
}

// formatarNumero escreve um número de telefone (só dígitos) para uma pessoa ler. Número do Brasil ganha o jeito de
// sempre: +55 44 98409-7902.
func formatarNumero(d string) string {
	if d == "" {
		return ""
	}
	if strings.HasPrefix(d, "55") && (len(d) == 12 || len(d) == 13) {
		resto := d[4:]
		corte := len(resto) - 4
		return fmt.Sprintf("+55 %s %s-%s", d[2:4], resto[:corte], resto[corte:])
	}
	return "+" + d
}
