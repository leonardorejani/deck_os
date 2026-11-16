package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types/events"
)

// Respondida pelo dono, a conversa tem de continuar fora das abas depois de reiniciar o ajudante.
func TestUltimaMinhaSobreviveAoReinicio(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	quando := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)
	e.Recebida("a@s.whatsapp.net", "Ana", false, Msg{Texto: "oi", ID: "1"}, quando)
	e.EnviadaMsg("a@s.whatsapp.net", "Ana", false, Msg{Texto: "oi, tudo bem", ID: "2", Minha: true}, quando.Add(time.Minute))
	if !porID(e.Recentes(), "a@s.whatsapp.net").UltimaMinha {
		t.Fatal("na memória a marca já tem de existir")
	}
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	if c := porID(NovoEstado(arq).Recentes(), "a@s.whatsapp.net"); c == nil || !c.UltimaMinha {
		t.Fatalf("depois de reiniciar a marca sumiu: %+v", c)
	}
}

// Dois pedidos da mesma mídia ao mesmo tempo baixam uma vez só e os dois recebem o arquivo.
func TestMidiaPedidaDuasVezesBaixaUmaVez(t *testing.T) {
	pasta := filepath.Join(t.TempDir(), "midia")
	b := &baixadorLento{dados: []byte("imagem")}
	m := msgDeFoto(t, 6)
	var wg sync.WaitGroup
	erros := make([]error, 6)
	for i := range erros {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, _, erros[i] = baixarMidia(context.Background(), b, pasta, "chat", m)
		}(i)
	}
	wg.Wait()
	for i, err := range erros {
		if err != nil {
			t.Fatalf("pedido %d falhou: %v", i, err)
		}
	}
	if n := atomic.LoadInt32(&b.vezes); n != 1 {
		t.Fatalf("baixou %d vezes, era para ser 1", n)
	}
}

type baixadorLento struct {
	dados []byte
	vezes int32
}

func (b *baixadorLento) Download(context.Context, whatsmeow.DownloadableMessage) ([]byte, error) {
	atomic.AddInt32(&b.vezes, 1)
	time.Sleep(80 * time.Millisecond)
	return b.dados, nil
}

// Versão recusada, falha de conexão e banimento temporário viram aviso em texto simples, sem jargão nem dado pessoal.
func TestAvisosDeConexaoQueNaoReconecta(t *testing.T) {
	casos := []struct {
		nome string
		ev   any
		tem  string
	}{
		{"versao", &events.ClientOutdated{}, "atualize o Deck"},
		{"falha", &events.ConnectFailure{Reason: events.ConnectFailureGeneric}, "Não consegui conectar"},
		{"banimento", &events.TemporaryBan{Code: events.TempBanBlockedByUsers, Expire: time.Hour}, "bloqueou"},
	}
	for _, c := range casos {
		t.Run(c.nome, func(t *testing.T) {
			var saiu []map[string]string
			antes := emitir
			emitir = func(v any) {
				if m, ok := v.(map[string]string); ok {
					saiu = append(saiu, m)
				}
			}
			defer func() { emitir = antes }()
			a, _ := ajudanteDeTeste(t)
			a.tratar(context.Background(), c.ev)
			if len(saiu) != 1 || saiu[0]["fase"] != "erro" {
				t.Fatalf("saiu %v", saiu)
			}
			d := saiu[0]["detalhe"]
			if !strings.Contains(strings.ToLower(d), strings.ToLower(c.tem)) {
				t.Fatalf("detalhe %q não diz %q", d, c.tem)
			}
			for _, jargao := range []string{"events.", "whatsmeow", "400", "101", "102"} {
				if strings.Contains(d, jargao) {
					t.Fatalf("jargão %q em %q", jargao, d)
				}
			}
		})
	}
}

// Sem mudança, o conversas.json não é regravado.
func TestSalvarNaoRegravaArquivoIgual(t *testing.T) {
	arq := filepath.Join(t.TempDir(), "conversas.json")
	e := NovoEstado(arq)
	e.Recebida("a@s.whatsapp.net", "Ana", false, Msg{Texto: "oi", ID: "1"}, time.Now())
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	passado := time.Now().Add(-time.Hour)
	_ = os.Chtimes(arq, passado, passado)
	if err := e.Salvar(); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(arq)
	if !info.ModTime().Before(time.Now().Add(-30 * time.Minute)) {
		t.Fatal("regravou um arquivo que não mudou")
	}
	e.Recebida("a@s.whatsapp.net", "Ana", false, Msg{Texto: "de novo", ID: "2"}, time.Now())
	_ = e.Salvar()
	if info, _ = os.Stat(arq); info.ModTime().Before(time.Now().Add(-30 * time.Minute)) {
		t.Fatal("não gravou depois de mudar")
	}
}

// A limpeza também corta por tamanho e poupa o que foi aberto agora (servido do cache).
func TestLimpezaDeMidiaCortaPorBytesEPoupaOLido(t *testing.T) {
	pasta := t.TempDir()
	grande := make([]byte, 8<<20)
	for i := 0; i < 16; i++ { // 128 MB, bem abaixo de 100 arquivos
		n := filepath.Join(pasta, string(rune('a'+i))+".jpg")
		_ = os.WriteFile(n, grande, 0o600)
		_ = os.Chtimes(n, t0.Add(time.Duration(i)*time.Second), t0.Add(time.Duration(i)*time.Second))
	}
	limparMidiasVelhas(pasta)
	var total int64
	itens, _ := os.ReadDir(pasta)
	for _, it := range itens {
		info, _ := it.Info()
		total += info.Size()
	}
	if total > maxBytesMidia {
		t.Fatalf("ficaram %d bytes (limite %d)", total, int64(maxBytesMidia))
	}

	// servir do cache renova o uso: o arquivo mais velho, se foi lido agora, sobrevive
	pasta = t.TempDir()
	b := &baixadorFalso{dados: []byte("x")}
	m := msgDeFoto(t, 1)
	arq, _, err := baixarMidia(context.Background(), b, pasta, "c", m)
	if err != nil {
		t.Fatal(err)
	}
	velho := time.Now().Add(-48 * time.Hour)
	_ = os.Chtimes(filepath.Join(pasta, arq), velho, velho)
	if _, _, err = baixarMidia(context.Background(), b, pasta, "c", m); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(filepath.Join(pasta, arq))
	if time.Since(info.ModTime()) > time.Hour {
		t.Fatal("ler do cache não renovou o horário de uso")
	}
}

// Quando o contato tira a foto, a antiga sai do disco e da lista.
func TestFotoRemovidaPeloContatoSaiDoDisco(t *testing.T) {
	pasta := t.TempDir()
	var tem atomic.Bool
	tem.Store(true)
	a := ajudanteDeFotos(t, pasta, 1, func(ctx context.Context, id string) ([]byte, error) {
		if tem.Load() {
			return []byte("jpg"), nil
		}
		return nil, errSemFoto
	})
	a.completar(context.Background())
	esperar(t, 2*time.Second, func() bool { return guardadas(a) == 1 })
	id := a.estado.Lista()[0].ID
	arq := filepath.Join(pasta, "fotos", arquivoDaFoto(id))
	tem.Store(false)
	velho := time.Now().Add(-48 * time.Hour)
	_ = os.Chtimes(arq, velho, velho)
	a.completar(context.Background())
	esperar(t, 2*time.Second, func() bool { return guardadas(a) == 0 })
	if _, err := os.Stat(arq); err == nil {
		t.Fatal("a foto antiga ficou no disco")
	}
}
