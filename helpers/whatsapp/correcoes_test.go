package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.mau.fi/whatsmeow/types/events"
)

// Sair pelo celular (LoggedOut) tem de apagar as conversas guardadas, senao elas ficam no disco sem tela para limpar.
func TestLoggedOutApagaAsConversasGuardadas(t *testing.T) {
	pasta := t.TempDir()
	arq := filepath.Join(pasta, "conversas.json")
	e := NovoEstado(arq)
	e.Recebida("a", "Ana", false, Msg{De: "", Texto: "segredo", Hora: "h"}, t0)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	marcarPareado(pasta, true)
	a := &ajudante{estado: e, pasta: pasta, sujo: make(chan struct{}, 1), grupos: map[string]string{}}
	a.tratar(context.Background(), &events.LoggedOut{})
	if b, err := os.ReadFile(arq); err == nil && strings.Contains(string(b), "segredo") {
		t.Fatalf("o conversas.json ainda tem o texto: %s", b)
	}
	if len(e.Lista()) != 0 {
		t.Fatal("o estado devia zerar")
	}
	if _, err := os.Stat(filepath.Join(pasta, "pareado")); err == nil {
		t.Fatal("o pareado devia sumir")
	}
	// Um QR novo nasce sem as conversas da sessao anterior.
	if len(NovoEstado(arq).Lista()) != 0 {
		t.Fatal("o estado novo recarregou conversa fantasma")
	}
}

func TestApagarSessaoNaoApagaAPastaSeOLogoutFalhar(t *testing.T) {
	pasta := filepath.Join(t.TempDir(), "sessao")
	if err := os.MkdirAll(pasta, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := apagarSessao(func() error { return errors.New("sem rede") }, pasta); err == nil {
		t.Fatal("devia devolver o erro do logout")
	}
	if _, err := os.Stat(pasta); err != nil {
		t.Fatal("a pasta nao pode sumir se o aparelho nao saiu")
	}
	if err := apagarSessao(func() error { return nil }, pasta); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(pasta); err == nil {
		t.Fatal("logout feito: a pasta devia sumir")
	}
}

// Rede fora na subida nao pode derrubar o ajudante: ele tenta de novo sozinho.
func TestConectaDeNovoSeARedeAindaNaoSubiu(t *testing.T) {
	chamadas, avisos := 0, 0
	ok := conectarComTentativas(context.Background(), func() error {
		chamadas++
		if chamadas < 3 {
			return errors.New("sem rede")
		}
		return nil
	}, func(int) time.Duration { return time.Millisecond }, func() { avisos++ })
	if !ok || chamadas != 3 || avisos != 2 {
		t.Fatalf("ok=%v chamadas=%d avisos=%d", ok, chamadas, avisos)
	}
}

func TestTentativasParamQuandoOContextoAcaba(t *testing.T) {
	ctx, parar := context.WithCancel(context.Background())
	ok := conectarComTentativas(ctx, func() error { parar(); return errors.New("x") },
		func(int) time.Duration { return time.Hour }, func() {})
	if ok {
		t.Fatal("contexto cancelado nao conecta")
	}
}

// O arquivo guarda so o que o Deck usa: conversa lida nao deixa texto no disco.
func TestSalvarNaoGravaConversaLida(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Recebida("a", "Ana", false, Msg{De: "", Texto: "texto da lida", Hora: "h"}, t0)
	e.Recebida("b", "Bia", false, Msg{De: "", Texto: "antiga", Hora: "h0"}, t0)
	e.Recebida("b", "Bia", false, Msg{De: "", Texto: "nova", Hora: "h1"}, t0.Add(time.Minute))
	e.Lida("a")
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(arq)
	s := string(b)
	if strings.Contains(s, "texto da lida") {
		t.Fatalf("conversa lida ficou no disco: %s", s)
	}
	if !strings.Contains(s, "antiga") || !strings.Contains(s, "nova") {
		t.Fatalf("a nao lida devia ficar: %s", s)
	}
}

// Mensagem nova não espera: a lista sai logo que o evento chega (antes esperava 300 ms de "juntar").
func TestMensagemNovaSaiNaHora(t *testing.T) {
	saiu := make(chan time.Time, 4)
	velho := emitir
	emitir = func(any) { saiu <- time.Now() }
	defer func() { emitir = velho }()
	a := &ajudante{estado: NovoEstado(""), sujo: make(chan struct{}, 1), grupos: map[string]string{}, tentadas: map[string]time.Time{}}
	ctx, parar := context.WithCancel(context.Background())
	defer parar()
	go a.publicar(ctx)
	ini := time.Now()
	a.marcarSujo()
	select {
	case quando := <-saiu:
		if d := quando.Sub(ini); d > 100*time.Millisecond {
			t.Fatalf("demorou %v para sair", d)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("a lista nunca saiu")
	}
}
