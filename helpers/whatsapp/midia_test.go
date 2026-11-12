package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"google.golang.org/protobuf/proto"
)

type baixadorFalso struct {
	dados []byte
	err   error
	vezes int
}

func (b *baixadorFalso) Download(context.Context, whatsmeow.DownloadableMessage) ([]byte, error) {
	b.vezes++
	return b.dados, b.err
}

func msgDeFoto(t *testing.T, tam uint64) Msg {
	t.Helper()
	c, _ := Analisar(&waE2E.Message{ImageMessage: &waE2E.ImageMessage{DirectPath: proto.String("/v/x"), Mimetype: proto.String("image/jpeg"), FileLength: proto.Uint64(tam)}}, false)
	a := &ajudante{}
	return a.mensagemDe(c, "", "M1", t0)
}

func TestBaixarMidiaGuardaComPermissaoRestritaEUsaOCache(t *testing.T) {
	pasta := filepath.Join(t.TempDir(), "midia")
	b := &baixadorFalso{dados: []byte("imagem")}
	m := msgDeFoto(t, 6)
	arq, tipo, err := baixarMidia(context.Background(), b, pasta, "a@s.whatsapp.net", m)
	if err != nil || tipo != "image/jpeg" || !strings.HasSuffix(arq, ".jpg") {
		t.Fatalf("arq=%q tipo=%q err=%v", arq, tipo, err)
	}
	if info, _ := os.Stat(filepath.Join(pasta, arq)); info == nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("o arquivo tem de existir com 0600: %v", info)
	}
	if _, _, err := baixarMidia(context.Background(), b, pasta, "a@s.whatsapp.net", m); err != nil || b.vezes != 1 {
		t.Fatalf("segunda vez tem de sair do cache: vezes=%d err=%v", b.vezes, err)
	}
}

func TestBaixarMidiaRespeitaOLimiteDeTamanho(t *testing.T) {
	b := &baixadorFalso{dados: []byte("x")}
	_, _, err := baixarMidia(context.Background(), b, t.TempDir(), "a", msgDeFoto(t, limiteMidia+1))
	if err == nil || b.vezes != 0 {
		t.Fatalf("passou do limite e nem devia baixar: err=%v vezes=%d", err, b.vezes)
	}
}

func TestVisualizacaoUnicaNuncaBaixa(t *testing.T) {
	vo := true
	c, _ := Analisar(&waE2E.Message{ImageMessage: &waE2E.ImageMessage{DirectPath: proto.String("/v/x"), ViewOnce: &vo}}, false)
	m := (&ajudante{}).mensagemDe(c, "", "M2", t0)
	if !m.Unica || m.Midia || m.Ref != nil {
		t.Fatalf("única não pode guardar referência: %+v", m)
	}
	// Mesmo que alguém monte uma mensagem à mão marcada como única, o download recusa.
	m.Midia, m.Ref = true, []byte("x")
	b := &baixadorFalso{dados: []byte("x")}
	if _, _, err := baixarMidia(context.Background(), b, t.TempDir(), "a", m); err == nil || b.vezes != 0 {
		t.Fatal("visualização única tem de ser recusada")
	}
}

func TestBaixarMidiaFalhaDeRedeNaoVazaDetalhe(t *testing.T) {
	b := &baixadorFalso{err: errors.New("dial tcp 1.2.3.4: segredo")}
	_, _, err := baixarMidia(context.Background(), b, t.TempDir(), "a", msgDeFoto(t, 3))
	if err == nil || strings.Contains(err.Error(), "segredo") {
		t.Fatalf("o erro não pode carregar detalhe da rede: %v", err)
	}
}

func TestMidiasVelhasSaem(t *testing.T) {
	pasta := t.TempDir()
	for i := 0; i < maxArquivosMidia+5; i++ {
		n := filepath.Join(pasta, strings.Repeat("a", 1)+string(rune('a'+i%26))+string(rune('a'+i/26))+".jpg")
		_ = os.WriteFile(n, []byte("x"), 0o600)
		_ = os.Chtimes(n, t0.Add(time.Duration(i)*time.Second), t0.Add(time.Duration(i)*time.Second))
	}
	limparMidiasVelhas(pasta)
	if itens, _ := os.ReadDir(pasta); len(itens) != maxArquivosMidia {
		t.Fatalf("ficaram %d arquivos", len(itens))
	}
}

// O celular escreve "Outro dispositivo" quando o tipo do aparelho é o desconhecido (o padrão da biblioteca).
func TestAparelhoApareceComoDeckOS(t *testing.T) {
	definirAparelho()
	if store.DeviceProps.GetOs() != "Deck OS" {
		t.Fatalf("nome: %q", store.DeviceProps.GetOs())
	}
	if store.DeviceProps.GetPlatformType() != waCompanionReg.DeviceProps_DESKTOP {
		t.Fatalf("tipo: %v", store.DeviceProps.GetPlatformType())
	}
}

func TestFotoDePerfilSoPorHttpsEComTeto(t *testing.T) {
	if _, err := baixarFoto(context.Background(), nil, "http://x/y.jpg"); err == nil {
		t.Fatal("http puro tem de ser recusado")
	}
	if a, b := arquivoDaFoto("a@s.whatsapp.net"), arquivoDaFoto("b@s.whatsapp.net"); a == b || strings.Contains(a, "whatsapp") {
		t.Fatalf("o nome do arquivo é hash: %q %q", a, b)
	}
}
