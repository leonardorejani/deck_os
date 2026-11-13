package main

import (
	"context"
	"math"
	"path/filepath"
	"testing"
	"time"

	"go.mau.fi/whatsmeow/proto/waHistorySync"
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

func ajudanteDeEventos(e *Estado) *ajudante {
	return &ajudante{estado: e, sujo: make(chan struct{}, 1), grupos: map[string]string{}}
}

// Arquivada e silenciada continua arquivada com mensagem nova (grupo barulhento), mesmo com "manter" desligado.
func TestArquivadaSilenciadaContinuaArquivadaComMensagemNova(t *testing.T) {
	e := NovoEstado("")
	a := ajudanteDeEventos(e)
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	id := jid.String()
	a.tratar(context.Background(), &events.Archive{JID: jid, Timestamp: t0, Action: &waSyncAction.ArchiveChatAction{Archived: ptr(true)}})
	a.tratar(context.Background(), &events.Mute{JID: jid, Timestamp: t0, Action: &waSyncAction.MuteAction{Muted: ptr(true), MuteEndTimestamp: ptr(int64(-1))}})
	e.Recebida(id, "Ana", false, Msg{Texto: "oi", Hora: "h"}, time.Now().Add(time.Hour))
	if l := e.Lista(); len(l) != 1 || !l[0].Arquivada {
		t.Fatalf("silenciada e arquivada tem de continuar arquivada: %+v", l)
	}
	// Tirar o silêncio devolve a regra comum: mensagem nova desarquiva.
	a.tratar(context.Background(), &events.Mute{JID: jid, Timestamp: t0, Action: &waSyncAction.MuteAction{Muted: ptr(false)}})
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("sem silêncio a mensagem nova desarquiva: %+v", l)
	}
}

// Silêncio com prazo vencido não vale mais. O prazo vem em segundos.
func TestSilencioVencidoNaoSeguraArquivada(t *testing.T) {
	e := NovoEstado("")
	a := ajudanteDeEventos(e)
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	a.tratar(context.Background(), &events.Archive{JID: jid, Timestamp: t0, Action: &waSyncAction.ArchiveChatAction{Archived: ptr(true)}})
	a.tratar(context.Background(), &events.Mute{JID: jid, Action: &waSyncAction.MuteAction{Muted: ptr(true), MuteEndTimestamp: ptr(t0.Add(time.Hour).Unix())}})
	e.Recebida(jid.String(), "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(2*time.Hour))
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("silêncio vencido não segura: %+v", l)
	}
}

// O silêncio vindo do histórico e o gravado em disco também valem.
func TestSilencioDoHistoricoPersiste(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.ArquivarEm("a", true, t0)
	e.Silenciar("a", math.MaxInt64)
	e.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(time.Hour))
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	if l := NovoEstado(arq).Lista(); len(l) != 1 || !l[0].Arquivada {
		t.Fatalf("silêncio tem de sobreviver: %+v", l)
	}
	if fimDoSilencio(true, 0) != math.MaxInt64 || fimDoSilencio(false, 5) != 0 || fimDoSilencio(true, 1000) != 1_000_000 {
		t.Fatal("conversão do fim do silêncio")
	}
}

// A Ultima nunca volta no tempo: mensagem fora de ordem ou histórico atrasado não reabrem a arquivada.
func TestUltimaNaoRegrideEArquivadaNaoVolta(t *testing.T) {
	e := NovoEstado("")
	e.ArquivarEm("a", true, t0)
	e.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(2*time.Hour))
	e.Recebida("a", "Ana", false, Msg{Texto: "atrasada", Hora: "h"}, t0.Add(-time.Hour))
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("mensagem fora de ordem não pode reabrir a arquivada: %+v", l)
	}
	f := NovoEstado("")
	f.ArquivarEm("a", true, t0.Add(time.Hour))
	f.Recebida("a", "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(2*time.Hour))
	f.Historico("a", "Ana", false, 1, t0.Add(30*time.Minute), nil)
	if l := f.Lista(); l[0].Arquivada {
		t.Fatalf("histórico atrasado não pode reabrir a arquivada: %+v", l)
	}
}

// UnarchiveChatsSetting vira "manter arquivadas" ao contrário, e sem Action (remoção) não mexe em nada.
func TestAjusteManterArquivadasPorEvento(t *testing.T) {
	e := NovoEstado("")
	a := ajudanteDeEventos(e)
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	e.ArquivarEm(jid.String(), true, t0)
	e.Recebida(jid.String(), "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(time.Hour))
	a.tratar(context.Background(), &events.UnarchiveChatsSetting{})
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("evento sem Action não liga manter: %+v", l)
	}
	a.tratar(context.Background(), &events.UnarchiveChatsSetting{Action: &waSyncAction.UnarchiveChatsSetting{UnarchiveChats: ptr(false)}})
	if l := e.Lista(); !l[0].Arquivada {
		t.Fatalf("UnarchiveChats desligado quer dizer manter arquivadas: %+v", l)
	}
	a.tratar(context.Background(), &events.UnarchiveChatsSetting{Action: &waSyncAction.UnarchiveChatsSetting{UnarchiveChats: ptr(true)}})
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("UnarchiveChats ligado quer dizer que mensagem nova desarquiva: %+v", l)
	}
}

// O instante do evento Archive é o que vale, não o "agora": arquivar antes da mensagem não segura a conversa.
func TestArquivarEventoUsaOTimestampDoEvento(t *testing.T) {
	e := NovoEstado("")
	a := ajudanteDeEventos(e)
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	e.Recebida(jid.String(), "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(time.Hour))
	a.tratar(context.Background(), &events.Archive{JID: jid, Timestamp: t0, Action: &waSyncAction.ArchiveChatAction{Archived: ptr(true)}})
	if l := e.Lista(); l[0].Arquivada {
		t.Fatalf("arquivou antes da mensagem, então já voltou a Todas: %+v", l)
	}
	a.tratar(context.Background(), &events.Archive{JID: jid, Timestamp: t0.Add(2 * time.Hour), Action: &waSyncAction.ArchiveChatAction{Archived: ptr(true)}})
	if l := e.Lista(); !l[0].Arquivada {
		t.Fatalf("arquivou depois da mensagem: %+v", l)
	}
}

// Histórico: a Ultima da conversa vira o instante do arquivamento, e o silêncio da conversa entra junto.
func TestHistoricoArquivadaESilenciada(t *testing.T) {
	e := NovoEstado("")
	a := ajudanteDeEventos(e)
	jid := types.NewJID("5544999990001", types.DefaultUserServer)
	conv := func(ts uint64, mudo uint64) *events.HistorySync {
		return &events.HistorySync{Data: &waHistorySync.HistorySync{Conversations: []*waHistorySync.Conversation{{
			ID: ptr(jid.String()), Name: ptr("Ana"), UnreadCount: ptr(uint32(1)), Archived: ptr(true),
			ConversationTimestamp: ptr(ts), MuteEndTime: ptr(mudo),
		}}}}
	}
	a.tratar(context.Background(), conv(uint64(t0.Unix()), 0))
	e.Recebida(jid.String(), "Ana", false, Msg{Texto: "oi", Hora: "h"}, t0.Add(time.Hour))
	if l := e.Lista(); len(l) != 1 || l[0].Arquivada {
		t.Fatalf("mensagem depois do arquivamento do histórico desarquiva: %+v", l)
	}
	a.tratar(context.Background(), conv(uint64(t0.Unix()), uint64(time.Now().Add(24*time.Hour).Unix())))
	if l := e.Lista(); !l[0].Arquivada {
		t.Fatalf("histórico com silêncio mantém arquivada: %+v", l)
	}
}
