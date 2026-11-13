package main

import (
	"context"
	"path/filepath"
	"testing"

	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
)

func ptr[T any](v T) *T { return &v }

// "O bullet de mensagens não lidas não deve contar as arquivadas": uma arquivada sem não lidas não ia para o disco, então
// depois de reabrir o Deck a primeira mensagem dela nascia como conversa comum e entrava em Todas e no total.
func TestArquivadaSemNaoLidasContinuaArquivadaDepoisDeReabrir(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0)
	e.Lida("a")
	e.Arquivar("a", true)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	novo := NovoEstado(arq) // o Deck fechou e abriu
	novo.Recebida("a", "Ana", false, Msg{Texto: "de novo", Hora: "h"}, t0)
	l := novo.Lista()
	if len(l) != 1 || !l[0].Arquivada {
		t.Fatalf("a mensagem nova de uma arquivada tem de continuar arquivada: %+v", l)
	}
}

func TestDesarquivarEsqueceEDesarquivarDesconhecidaNaoCriaLinha(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Arquivar("a", true)
	e.Arquivar("a", false)
	e.Arquivar("nunca-vista", false)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	n := NovoEstado(arq)
	n.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0)
	if l := n.Lista(); len(l) != 1 || l[0].Arquivada {
		t.Fatalf("desarquivada volta a ser comum: %+v", l)
	}
	if _, ok := n.conversas["nunca-vista"]; ok {
		t.Fatal("desarquivar conversa desconhecida não pode criar conversa")
	}
}

func TestSairDoAparelhoEsqueceAsArquivadas(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Arquivar("a", true)
	_ = e.Salvar()
	e.Limpar()
	n := NovoEstado(arq)
	n.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0)
	if n.Lista()[0].Arquivada {
		t.Fatal("a conta nova não herda as arquivadas da anterior")
	}
}

// O evento Archive vindo da sincronização completa (que antes nem era emitida) marca a conversa, e o retrato de
// leitura dessa mesma sincronização não zera as não lidas que chegaram depois.
func TestArquivadaDaSincronizacaoCompletaEntraELeituraAntigaNaoZeraNaoLidas(t *testing.T) {
	e := NovoEstado("")
	a := &ajudante{estado: e, sujo: make(chan struct{}, 1), grupos: map[string]string{}}
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	e.Recebida(jid.String(), "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0)
	a.tratar(context.Background(), &events.Archive{JID: jid, FromFullSync: true, Action: &waSyncAction.ArchiveChatAction{Archived: ptr(true)}})
	a.tratar(context.Background(), &events.MarkChatAsRead{JID: jid, FromFullSync: true, Action: &waSyncAction.MarkChatAsReadAction{Read: ptr(true)}})
	l := e.Lista()
	if len(l) != 1 || !l[0].Arquivada || l[0].NaoLidas != 1 {
		t.Fatalf("esperava arquivada com 1 não lida: %+v", l)
	}
	// Leitura de verdade (não da sincronização completa) continua zerando.
	a.tratar(context.Background(), &events.MarkChatAsRead{JID: jid, Action: &waSyncAction.MarkChatAsReadAction{Read: ptr(true)}})
	if len(e.Lista()) != 0 {
		t.Fatal("ler no celular zera as não lidas")
	}
}
