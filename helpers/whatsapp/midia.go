package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"google.golang.org/protobuf/proto"
)

// Foto de perfil e mídia ficam na pasta da sessão (0700), com nome feito de hash: o nome do arquivo não conta nada
// sobre quem é a conversa. Só leitura: nada daqui envia ou marca algo.

func hashCurto(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:8])
}

func arquivoDaFoto(jid string) string { return hashCurto("foto:"+jid) + ".jpg" }

// guardarArquivo grava com permissão restrita, por um arquivo temporário (nunca deixa meio arquivo à vista).
func guardarArquivo(pasta, nome string, dados []byte) error {
	if err := os.MkdirAll(pasta, 0o700); err != nil {
		return err
	}
	_ = os.Chmod(pasta, 0o700)
	tmp := filepath.Join(pasta, nome+".tmp")
	if err := os.WriteFile(tmp, dados, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(pasta, nome))
}

const limiteFoto = 2 << 20

// baixarFoto pega a foto de perfil do endereço que o WhatsApp deu. Só https, e com teto de tamanho.
func baixarFoto(ctx context.Context, c *http.Client, endereco string) ([]byte, error) {
	u, err := url.Parse(endereco)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return nil, errors.New("endereço inválido")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endereco, nil)
	if err != nil {
		return nil, err
	}
	r, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer r.Body.Close()
	if r.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", r.StatusCode)
	}
	dados, err := io.ReadAll(io.LimitReader(r.Body, limiteFoto+1))
	if err != nil || len(dados) == 0 || len(dados) > limiteFoto {
		return nil, errors.New("foto fora do limite")
	}
	return dados, nil
}

// baixador é o que a whatsmeow oferece para baixar (e que os testes trocam por um falso).
type baixador interface {
	Download(ctx context.Context, msg whatsmeow.DownloadableMessage) ([]byte, error)
}

var tipoValido = regexp.MustCompile(`^(image|audio)/[a-z0-9.+-]+(; ?codecs=[a-z0-9.,+ -]+)?$`)

func extensao(tipo string) string {
	base := strings.SplitN(tipo, ";", 2)[0]
	switch base {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "audio/ogg":
		return ".ogg"
	case "audio/mp4", "audio/aac", "audio/x-m4a":
		return ".m4a"
	case "audio/mpeg":
		return ".mp3"
	}
	return ".bin"
}

// baixarMidia baixa a foto ou o áudio de uma mensagem (só os comuns: visualização única não tem referência) para a
// pasta `midia`, até o limite de tamanho. Devolve o arquivo e o tipo.
func baixarMidia(ctx context.Context, b baixador, pasta, chat string, m Msg) (arquivo, tipo string, err error) {
	if m.Unica || !m.Midia || len(m.Ref) == 0 {
		return "", "", errors.New("Essa mídia não abre aqui.")
	}
	var dm whatsmeow.DownloadableMessage
	var tam uint64
	switch m.Tipo {
	case "foto":
		x := &waE2E.ImageMessage{}
		if proto.Unmarshal(m.Ref, x) != nil {
			return "", "", errors.New("Não consegui ler essa foto.")
		}
		dm, tam, tipo = x, x.GetFileLength(), x.GetMimetype()
		if tipo == "" {
			tipo = "image/jpeg"
		}
	case "audio":
		x := &waE2E.AudioMessage{}
		if proto.Unmarshal(m.Ref, x) != nil {
			return "", "", errors.New("Não consegui ler esse áudio.")
		}
		dm, tam, tipo = x, x.GetFileLength(), x.GetMimetype()
		if tipo == "" {
			tipo = "audio/ogg"
		}
	default:
		return "", "", errors.New("Essa mídia não abre aqui.")
	}
	tipo = strings.ToLower(strings.TrimSpace(tipo))
	if !tipoValido.MatchString(tipo) {
		return "", "", errors.New("Tipo de mídia que o Deck não abre.")
	}
	if tam > limiteMidia {
		return "", "", errors.New("Arquivo grande demais para abrir aqui.")
	}
	arquivo = hashCurto("midia:"+chat+":"+m.ID) + extensao(tipo)
	caminho := filepath.Join(pasta, arquivo)
	if info, e := os.Stat(caminho); e == nil && info.Size() > 0 {
		return arquivo, tipo, nil
	}
	dados, e := b.Download(ctx, dm)
	if e != nil {
		return "", "", errors.New("Não consegui baixar. Tente de novo em instantes.")
	}
	if len(dados) > limiteMidia {
		return "", "", errors.New("Arquivo grande demais para abrir aqui.")
	}
	if e := guardarArquivo(pasta, arquivo, dados); e != nil {
		return "", "", errors.New("Não consegui guardar o arquivo.")
	}
	limparMidiasVelhas(pasta)
	return arquivo, tipo, nil
}

// limparMidiasVelhas mantém só os arquivos mais novos da pasta de mídia.
func limparMidiasVelhas(pasta string) {
	itens, err := os.ReadDir(pasta)
	if err != nil || len(itens) <= maxArquivosMidia {
		return
	}
	sort.Slice(itens, func(i, j int) bool {
		a, _ := itens[i].Info()
		b, _ := itens[j].Info()
		return a != nil && b != nil && a.ModTime().Before(b.ModTime())
	})
	for _, it := range itens[:len(itens)-maxArquivosMidia] {
		_ = os.Remove(filepath.Join(pasta, it.Name()))
	}
}
