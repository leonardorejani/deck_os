package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

var t0 = time.Date(2026, 11, 12, 10, 0, 0, 0, time.UTC)

func TestListaSoComNaoLidasEOrdenada(t *testing.T) {
	e := NovoEstado("")
	e.Historico("a", "Ana", false, 2, t0, []Msg{{De: "", Texto: "oi", Hora: "h1"}, {De: "", Texto: "tudo bem?", Hora: "h2"}, {De: "", Texto: "antiga", Hora: "h0"}})
	e.Historico("b", "Grupo", true, 0, t0.Add(time.Hour), []Msg{{De: "x", Texto: "lida", Hora: "h"}})
	e.Recebida("c", "Caio", false, Msg{De: "", Texto: "novo", Hora: "h3"}, t0.Add(2*time.Minute))
	l := e.Lista()
	if len(l) != 2 || l[0].ID != "c" || l[1].ID != "a" {
		t.Fatalf("lista errada: %+v", l)
	}
	if len(l[1].Mensagens) != 2 {
		t.Fatalf("devia trazer só as 2 não lidas, veio %d", len(l[1].Mensagens))
	}
}

func TestLidaEEnviadaZeram(t *testing.T) {
	e := NovoEstado("")
	e.Recebida("a", "Ana", false, Msg{De: "", Texto: "oi", Hora: "h"}, t0)
	e.Recebida("b", "Bia", false, Msg{De: "", Texto: "oi", Hora: "h"}, t0)
	e.Lida("a")
	e.Enviada("b", t0.Add(time.Minute))
	if len(e.Lista()) != 0 {
		t.Fatal("conversas lidas não podem aparecer")
	}
	e.MarcadaNaoLida("a")
	if l := e.Lista(); len(l) != 1 || l[0].NaoLidas != 1 {
		t.Fatalf("marcada como não lida devia contar 1: %+v", l)
	}
}

func TestGrupoNuncaVoltaParaContato(t *testing.T) {
	e := NovoEstado("")
	e.Historico("g", "Louvor", true, 1, t0, nil)
	e.Recebida("g", "", false, Msg{De: "Ana", Texto: "oi", Hora: "h"}, t0)
	if !e.Lista()[0].Grupo || e.Lista()[0].Nome != "Louvor" {
		t.Fatal("grupo e nome têm que se manter")
	}
}

func TestTetoDeMensagens(t *testing.T) {
	e := NovoEstado("")
	for i := 0; i < maxMensagens+20; i++ {
		e.Recebida("a", "Ana", false, Msg{De: "", Texto: "m", Hora: "h"}, t0)
	}
	if n := len(e.conversas["a"].Mensagens); n != maxMensagens {
		t.Fatalf("guardou %d mensagens", n)
	}
}

func TestPersistenciaComPermissaoRestrita(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Recebida("a", "Ana", false, Msg{De: "", Texto: "oi", Hora: "h"}, t0)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(arq)
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("permissão %v, esperado 0600", info.Mode().Perm())
	}
	if l := NovoEstado(arq).Lista(); len(l) != 1 || l[0].Nome != "Ana" {
		t.Fatalf("não recarregou: %+v", l)
	}
}

// Conversa sem nome (contato só com LID, ainda sem nome salvo) nunca vira linha em branco: mostra o número.
func TestConversaSemNomeMostraONumero(t *testing.T) {
	e := NovoEstado("")
	e.Recebida("1@lid", "", false, Msg{De: "", Texto: "oi", Hora: "h"}, t0)
	e.Numero("1@lid", "5544984097902")
	if l := e.Lista(); l[0].Nome != "+55 44 98409-7902" {
		t.Fatalf("nome: %q", l[0].Nome)
	}
	e.Recebida("1@lid", "Ana", false, Msg{De: "", Texto: "oi", Hora: "h"}, t0)
	if l := e.Lista(); l[0].Nome != "Ana" {
		t.Fatalf("o nome de verdade tem que ganhar do número: %q", l[0].Nome)
	}
}

func TestArquivadaSegueNaListaMarcadaEMidiaNaoVazaReferencia(t *testing.T) {
	e := NovoEstado("")
	e.Recebida("a", "Ana", false, Msg{Texto: "Foto", Hora: "h", ID: "M1", Tipo: "foto", Midia: true, Ref: []byte("segredo")}, t0)
	e.Arquivar("a", true)
	l := e.Lista()
	if len(l) != 1 || !l[0].Arquivada {
		t.Fatalf("arquivada: %+v", l)
	}
	if l[0].Mensagens[0].Ref != nil {
		t.Fatal("a referência da mídia não pode ir para o núcleo")
	}
	if m, ok := e.Achar("a", "M1"); !ok || string(m.Ref) != "segredo" {
		t.Fatal("o ajudante tem de achar a referência para baixar")
	}
	e.Arquivar("a", false)
	if e.Lista()[0].Arquivada {
		t.Fatal("desarquivar")
	}
}
