package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.mau.fi/whatsmeow/proto/waCommon"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"
)

func ajudanteDeTeste(t *testing.T) (*ajudante, *Estado) {
	t.Helper()
	e := NovoEstado(filepath.Join(t.TempDir(), "conversas.json"))
	return &ajudante{estado: e, pasta: t.TempDir(), sujo: make(chan struct{}, 1), grupos: map[string]string{}, tentadas: map[string]time.Time{}}, e
}

var (
	contatoA = types.NewJID("5500000000001", types.DefaultUserServer)
	contatoB = types.NewJID("5500000000002", types.DefaultUserServer)
	grupoG   = types.NewJID("120363000000000001", types.GroupServer)
)

func histMsg(id, texto string, deMim bool, ts int64, participante string) *waHistorySync.HistorySyncMsg {
	return &waHistorySync.HistorySyncMsg{Message: &waWeb.WebMessageInfo{
		Key:              &waCommon.MessageKey{ID: proto.String(id), FromMe: proto.Bool(deMim)},
		Message:          &waE2E.Message{Conversation: proto.String(texto)},
		MessageTimestamp: proto.Uint64(uint64(ts)),
		Participant:      proto.String(participante),
	}}
}

func historia(conv ...*waHistorySync.Conversation) *events.HistorySync {
	return &events.HistorySync{Data: &waHistorySync.HistorySync{Conversations: conv}}
}

func msgAoVivo(chat types.JID, id, texto string, deMim bool, quando time.Time) *events.Message {
	return &events.Message{
		Info:    types.MessageInfo{MessageSource: types.MessageSource{Chat: chat, Sender: chat, IsFromMe: deMim, IsGroup: chat.Server == types.GroupServer}, ID: id, Timestamp: quando},
		Message: &waE2E.Message{Conversation: proto.String(texto)},
	}
}

func porID(l []Conversa, id string) *Conversa {
	for i := range l {
		if l[i].ID == id {
			return &l[i]
		}
	}
	return nil
}

// Todas lista as conversas lidas e as não lidas, na ordem da última mensagem, cada uma com a prévia.
func TestRecentesTrazLidasENaoLidasEmOrdem(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC).Unix()
	a.tratar(context.Background(), historia(
		&waHistorySync.Conversation{ID: proto.String(contatoA.String()), Name: proto.String("Ana"), UnreadCount: proto.Uint32(0), ConversationTimestamp: proto.Uint64(uint64(base)),
			Messages: []*waHistorySync.HistorySyncMsg{histMsg("m1", "ate mais", true, base, "")}},
		&waHistorySync.Conversation{ID: proto.String(grupoG.String()), Name: proto.String("Equipe"), UnreadCount: proto.Uint32(2), ConversationTimestamp: proto.Uint64(uint64(base + 60)),
			Messages: []*waHistorySync.HistorySyncMsg{histMsg("g1", "oi", false, base+30, contatoB.String()), histMsg("g2", "bora", false, base+60, contatoB.String())}},
		&waHistorySync.Conversation{ID: proto.String(contatoB.String()), Name: proto.String("Beto"), UnreadCount: proto.Uint32(0), ConversationTimestamp: proto.Uint64(uint64(base - 3600)),
			Messages: []*waHistorySync.HistorySyncMsg{histMsg("b1", "valeu", false, base-3600, "")}},
	))
	l := e.Recentes()
	if len(l) != 3 || l[0].ID != grupoG.String() || l[1].ID != contatoA.String() || l[2].ID != contatoB.String() {
		t.Fatalf("ordem errada: %+v", l)
	}
	if len(e.Lista()) != 1 {
		t.Fatalf("Lista (só não lidas) devia ter 1: %d", len(e.Lista()))
	}
	g := l[0]
	if g.NaoLidas != 2 || len(g.Mensagens) != 2 || !g.Grupo {
		t.Fatalf("grupo: %+v", g)
	}
	ana := l[1]
	if ana.NaoLidas != 0 || len(ana.Mensagens) != 1 || ana.Mensagens[0].Texto != "ate mais" {
		t.Fatalf("lida com prévia: %+v", ana)
	}
	if ana.Previa != nil {
		t.Fatal("a prévia não vai duplicada na resposta")
	}
}

// Mensagem nova de conversa lida vira não lida; ler no celular zera e a conversa continua na lista, com a prévia.
func TestMensagemNovaELeituraNoCelular(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), historia(&waHistorySync.Conversation{ID: proto.String(contatoA.String()), Name: proto.String("Ana"), UnreadCount: proto.Uint32(0),
		ConversationTimestamp: proto.Uint64(uint64(base.Unix())), Messages: []*waHistorySync.HistorySyncMsg{histMsg("m1", "oi", false, base.Unix(), "")}}))
	a.tratar(context.Background(), msgAoVivo(contatoA, "m2", "tudo bem?", false, base.Add(time.Minute)))
	c := porID(e.Recentes(), contatoA.String())
	if c == nil || c.NaoLidas != 1 || c.Mensagens[len(c.Mensagens)-1].Texto != "tudo bem?" {
		t.Fatalf("depois da mensagem: %+v", c)
	}
	// Leu no celular (recibo de leitura do próprio dono, depois da mensagem).
	a.tratar(context.Background(), &events.Receipt{MessageSource: types.MessageSource{Chat: contatoA, IsFromMe: true}, Type: types.ReceiptTypeReadSelf, Timestamp: base.Add(2 * time.Minute)})
	c = porID(e.Recentes(), contatoA.String())
	if c == nil || c.NaoLidas != 0 || len(c.Mensagens) != 1 || c.Mensagens[0].Texto != "tudo bem?" {
		t.Fatalf("depois de ler: %+v", c)
	}
	if len(e.Lista()) != 0 {
		t.Fatal("ninguém com não lidas")
	}
}

// Leitura pelo app state (marcar como lida) também zera, e marcar como não lida volta a 1.
func TestMarcarComoLidaPeloCelular(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), msgAoVivo(contatoA, "m1", "oi", false, base))
	a.tratar(context.Background(), &events.MarkChatAsRead{JID: contatoA, Timestamp: base.Add(time.Minute), Action: &waSyncAction.MarkChatAsReadAction{Read: proto.Bool(true)}})
	if c := porID(e.Recentes(), contatoA.String()); c == nil || c.NaoLidas != 0 {
		t.Fatalf("devia estar lida: %+v", c)
	}
	a.tratar(context.Background(), &events.MarkChatAsRead{JID: contatoA, Timestamp: base.Add(2 * time.Minute), Action: &waSyncAction.MarkChatAsReadAction{Read: proto.Bool(false)}})
	if c := porID(e.Recentes(), contatoA.String()); c == nil || c.NaoLidas != 1 {
		t.Fatalf("devia voltar a 1: %+v", c)
	}
}

// Leitura antiga que chega atrasada (a fila de quando o ajudante reconecta) não apaga a mensagem que veio depois dela.
func TestLeituraAtrasadaNaoZeraMensagemMaisNova(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), msgAoVivo(contatoA, "m1", "oi", false, base.Add(10*time.Minute)))
	a.tratar(context.Background(), &events.Receipt{MessageSource: types.MessageSource{Chat: contatoA, IsFromMe: true}, Type: types.ReceiptTypeReadSelf, Timestamp: base})
	a.tratar(context.Background(), &events.MarkChatAsRead{JID: contatoA, Timestamp: base, Action: &waSyncAction.MarkChatAsReadAction{Read: proto.Bool(true)}})
	if c := porID(e.Recentes(), contatoA.String()); c == nil || c.NaoLidas != 1 {
		t.Fatalf("a não lida mais nova sumiu: %+v", c)
	}
}

// Histórico mais velho que a mensagem que já chegou ao vivo não zera a não lida.
func TestHistoricoVelhoNaoZeraNaoLidaDeAgora(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), msgAoVivo(contatoA, "m2", "nova", false, base.Add(time.Hour)))
	a.tratar(context.Background(), historia(&waHistorySync.Conversation{ID: proto.String(contatoA.String()), Name: proto.String("Ana"), UnreadCount: proto.Uint32(0),
		ConversationTimestamp: proto.Uint64(uint64(base.Unix())), Messages: []*waHistorySync.HistorySyncMsg{histMsg("m1", "velha", false, base.Unix(), "")}}))
	c := porID(e.Recentes(), contatoA.String())
	if c == nil || c.NaoLidas != 1 || c.Mensagens[len(c.Mensagens)-1].Texto != "nova" {
		t.Fatalf("o histórico velho apagou a não lida: %+v", c)
	}
}

// Arquivar tira de Todas (fica com a marca) e fixar sobe a marca; as duas vêm do celular.
func TestArquivarEFixarPeloCelular(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), msgAoVivo(contatoA, "m1", "oi", false, base))
	a.tratar(context.Background(), msgAoVivo(contatoB, "m2", "oi", false, base))
	a.tratar(context.Background(), &events.Archive{JID: contatoA, Timestamp: base.Add(time.Minute), Action: &waSyncAction.ArchiveChatAction{Archived: proto.Bool(true)}})
	a.tratar(context.Background(), &events.Pin{JID: contatoB, Timestamp: base, Action: &waSyncAction.PinAction{Pinned: proto.Bool(true)}})
	l := e.Recentes()
	if !porID(l, contatoA.String()).Arquivada || porID(l, contatoB.String()).Arquivada {
		t.Fatalf("arquivada errada: %+v", l)
	}
	if !porID(l, contatoB.String()).Fixada || porID(l, contatoA.String()).Fixada {
		t.Fatalf("fixada errada: %+v", l)
	}
	a.tratar(context.Background(), &events.Pin{JID: contatoB, Timestamp: base, Action: &waSyncAction.PinAction{Pinned: proto.Bool(false)}})
	if porID(e.Recentes(), contatoB.String()).Fixada {
		t.Fatal("devia desafixar")
	}
}

// O que o dono escreve no celular vira a prévia (e em grupo leva "Você"), e a conversa lida passa a existir.
func TestMensagemDoDonoViraPrevia(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), msgAoVivo(grupoG, "g1", "oi", false, base))
	a.tratar(context.Background(), msgAoVivo(grupoG, "g2", "chego já", true, base.Add(time.Minute)))
	a.tratar(context.Background(), msgAoVivo(contatoA, "m1", "fechado", true, base))
	l := e.Recentes()
	g, ana := porID(l, grupoG.String()), porID(l, contatoA.String())
	if g == nil || g.NaoLidas != 0 || g.Mensagens[0].Texto != "chego já" || g.Mensagens[0].De != "Você" {
		t.Fatalf("grupo: %+v", g)
	}
	if ana == nil || ana.NaoLidas != 0 || ana.Mensagens[0].Texto != "fechado" || ana.Mensagens[0].De != "" {
		t.Fatalf("contato: %+v", ana)
	}
}

// Mensagem que chegou mas não abriu conta como não lida, e abrir depois não conta de novo.
func TestMensagemIndecifravelContaUmaVez(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	a.tratar(context.Background(), &events.UndecryptableMessage{Info: types.MessageInfo{MessageSource: types.MessageSource{Chat: contatoA, Sender: contatoA}, ID: "x1", Timestamp: base}})
	if c := porID(e.Recentes(), contatoA.String()); c == nil || c.NaoLidas != 1 {
		t.Fatalf("a indecifrável devia contar: %+v", c)
	}
	a.tratar(context.Background(), msgAoVivo(contatoA, "x1", "abriu", false, base))
	c := porID(e.Recentes(), contatoA.String())
	if c.NaoLidas != 1 || len(c.Mensagens) != 1 || c.Mensagens[0].Texto != "abriu" {
		t.Fatalf("contou de novo ou não trocou: %+v", c)
	}
}

// As lidas ficam no disco só com a prévia, voltam depois de reiniciar e o conversas.json segue sem texto de lida.
func TestLidasSobrevivemAoReinicioSoComPrevia(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	e.Historico(contatoA.String(), "Ana", false, 0, base, nil)
	e.Previa(contatoA.String(), Msg{Texto: strings.Repeat("a", 500), Hora: hora(base), ID: "m1", Ref: []byte("segredo-de-midia")})
	e.Fixar(contatoA.String(), true)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(arq); strings.Contains(string(b), "aaaa") {
		t.Fatalf("conversa lida no conversas.json: %s", b)
	}
	rec, err := os.ReadFile(arq + ".recentes")
	if err != nil || strings.Contains(string(rec), "segredo-de-midia") || len(rec) > 1000 {
		t.Fatalf("recentes.json: %v %d", err, len(rec))
	}
	info, _ := os.Stat(arq + ".recentes")
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("permissão %v", info.Mode().Perm())
	}
	n := NovoEstado(arq)
	c := porID(n.Recentes(), contatoA.String())
	if c == nil || c.Nome != "Ana" || len(c.Mensagens) != 1 || len([]rune(c.Mensagens[0].Texto)) != maxPrevia || !c.Fixada {
		t.Fatalf("depois do reinício: %+v", c)
	}
}

// A lista leva as maxRecentes mais novas (e as com não lidas, sempre), nesta ordem.
func TestRecentesTemLimite(t *testing.T) {
	e := NovoEstado("")
	base := time.Date(2026, 11, 16, 0, 0, 0, 0, time.UTC)
	for i := 0; i < maxRecentes+30; i++ {
		id := fmt.Sprintf("c%03d", i)
		e.Historico(id, id, false, 0, base.Add(time.Duration(i)*time.Minute), nil)
		e.Previa(id, Msg{Texto: "x", Hora: hora(base.Add(time.Duration(i) * time.Minute)), ID: id})
	}
	e.Historico("antiga", "Antiga", false, 3, base.Add(-time.Hour), []Msg{{Texto: "x", Hora: hora(base)}})
	l := e.Recentes()
	if len(l) != maxRecentes+1 {
		t.Fatalf("len=%d", len(l))
	}
	if l[0].ID != "c229" || porID(l, "antiga") == nil || porID(l, "c000") != nil {
		t.Fatalf("recorte errado: primeira=%s", l[0].ID)
	}
}

// Documento com legenda e mensagem de conversa temporária chegam embrulhados no histórico e também contam.
func TestAnalisarDesembrulhaTemporariaEDocumentoComLegenda(t *testing.T) {
	doc := &waE2E.Message{DocumentWithCaptionMessage: &waE2E.FutureProofMessage{Message: &waE2E.Message{DocumentMessage: &waE2E.DocumentMessage{Caption: proto.String("contrato")}}}}
	if c, ok := Analisar(doc, false); !ok || c.Texto != "contrato" {
		t.Fatalf("documento: %+v %v", c, ok)
	}
	tmp := &waE2E.Message{EphemeralMessage: &waE2E.FutureProofMessage{Message: &waE2E.Message{Conversation: proto.String("some em 24h")}}}
	if c, ok := Analisar(tmp, false); !ok || c.Texto != "some em 24h" {
		t.Fatalf("temporária: %+v %v", c, ok)
	}
}

// UltimaMinha: a conversa respondida pelo dono sai marcada, e a mensagem nova do contato desliga a marca. Vale para o
// histórico, para o que o dono escreve ao vivo e para a mídia que a mensagem não decifra (só zera a conversa).
func TestUltimaMinhaSegueQuemFalouPorUltimo(t *testing.T) {
	a, e := ajudanteDeTeste(t)
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	// histórico: A terminou com mensagem do dono, B com mensagem do contato
	a.tratar(context.Background(), historia(
		&waHistorySync.Conversation{ID: proto.String(contatoA.String()), Name: proto.String("Ana"), UnreadCount: proto.Uint32(0), ConversationTimestamp: proto.Uint64(uint64(base.Unix())),
			Messages: []*waHistorySync.HistorySyncMsg{histMsg("m1", "ate mais", true, base.Unix(), "")}},
		&waHistorySync.Conversation{ID: proto.String(contatoB.String()), Name: proto.String("Beto"), UnreadCount: proto.Uint32(0), ConversationTimestamp: proto.Uint64(uint64(base.Unix() - 60)),
			Messages: []*waHistorySync.HistorySyncMsg{histMsg("b1", "valeu", false, base.Unix()-60, "")}},
	))
	l := e.Recentes()
	if ana, beto := porID(l, contatoA.String()), porID(l, contatoB.String()); !ana.UltimaMinha || beto.UltimaMinha {
		t.Fatalf("histórico: ana=%v beto=%v", ana.UltimaMinha, beto.UltimaMinha)
	}
	// o contato escreve: sai de "minha"
	a.tratar(context.Background(), msgAoVivo(contatoA, "m2", "tudo bem?", false, base.Add(time.Minute)))
	if ana := porID(e.Recentes(), contatoA.String()); ana.UltimaMinha || ana.NaoLidas != 1 {
		t.Fatalf("depois do contato: %+v", ana)
	}
	// o dono responde: volta
	a.tratar(context.Background(), msgAoVivo(contatoA, "m3", "tudo", true, base.Add(2*time.Minute)))
	if ana := porID(e.Recentes(), contatoA.String()); !ana.UltimaMinha || ana.NaoLidas != 0 {
		t.Fatalf("depois do dono: %+v", ana)
	}
	// grupo e contato novo, escritos ao vivo pelo dono
	a.tratar(context.Background(), msgAoVivo(grupoG, "g1", "oi", false, base))
	a.tratar(context.Background(), msgAoVivo(grupoG, "g2", "chego já", true, base.Add(time.Minute)))
	if g := porID(e.Recentes(), grupoG.String()); !g.UltimaMinha {
		t.Fatalf("grupo: %+v", g)
	}
	// o campo sai no JSON só quando é verdade
	b, _ := json.Marshal(porID(e.Recentes(), contatoB.String()))
	if strings.Contains(string(b), "ultimaMinha") {
		t.Fatalf("beto não devia levar o campo: %s", b)
	}
	b, _ = json.Marshal(porID(e.Recentes(), contatoA.String()))
	if !strings.Contains(string(b), `"ultimaMinha":true`) {
		t.Fatalf("ana devia levar o campo: %s", b)
	}
}

// Resposta do dono sem conteúdo que o ajudante entende (só zera a conversa) também conta como "respondi".
func TestEnviadaSemConteudoMarcaUltimaMinha(t *testing.T) {
	e := NovoEstado("")
	base := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	e.Recebida(contatoA.String(), "Ana", false, Msg{Texto: "oi", Hora: base.Format(time.RFC3339), ID: "a1"}, base)
	e.Enviada(contatoA.String(), base.Add(time.Minute))
	if c := porID(e.Recentes(), contatoA.String()); !c.UltimaMinha || c.NaoLidas != 0 {
		t.Fatalf("%+v", c)
	}
	// resposta atrasada (mais velha que a última) não marca
	e.Recebida(contatoB.String(), "Beto", false, Msg{Texto: "oi", Hora: base.Format(time.RFC3339), ID: "b1"}, base.Add(time.Hour))
	e.Enviada(contatoB.String(), base)
	if c := porID(e.Recentes(), contatoB.String()); c.UltimaMinha {
		t.Fatalf("atrasada não marca: %+v", c)
	}
}
