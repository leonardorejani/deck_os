package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/types"
)

// Foto de perfil das conversas da lista. Antes: uma por vez, com pausa entre elas, fila que descartava em silêncio e
// qualquer falha (até de rede) valendo como "sem foto" por 6 horas. Agora:
//   - até vagasDeFoto baixam ao mesmo tempo e a fila não descarta ninguém;
//   - quem esconde a foto (WhatsApp responde que não há ou que não pode ver) vai para um arquivo no disco e só é
//     perguntado de novo daqui a esperaSemFoto, mesmo depois de reiniciar;
//   - falha de rede é outra coisa: tenta de novo logo (30 s, dobrando até 10 min), sem ficar marcada como sem foto.
const (
	vagasDeFoto    = 4
	esperaSemFoto  = 7 * 24 * time.Hour
	esperaFalhaMin = 30 * time.Second
	esperaFalhaMax = 10 * time.Minute
	prazoDaFoto    = 10 * time.Second
	arquivoSemFoto = "sem-foto.json"
)

var errSemFoto = errors.New("sem foto")

// Uma gravação de sem-foto.json por vez: elas usam o mesmo arquivo temporário.
var gravandoSemFoto sync.Mutex

// iniciarFotos liga as estruturas na primeira vez (com a trava de a.mu na mão de quem chama).
func (a *ajudante) iniciarFotos() {
	if a.emFila != nil {
		return
	}
	a.emFila = map[string]bool{}
	a.vagasFoto = make(chan struct{}, vagasDeFoto)
	a.falhasFoto = map[string]int{}
	a.semFoto = map[string]time.Time{}
	if a.pasta != "" {
		if b, err := os.ReadFile(filepath.Join(a.pasta, "fotos", arquivoSemFoto)); err == nil {
			var m map[string]int64
			if json.Unmarshal(b, &m) == nil {
				for id, t := range m {
					a.semFoto[id] = time.Unix(t, 0)
				}
			}
		}
	}
	if a.pegarFoto == nil {
		cliente := &http.Client{Timeout: prazoDaFoto}
		a.pegarFoto = func(ctx context.Context, id string) ([]byte, error) { return a.baixarMiniatura(ctx, cliente, id) }
	}
	if a.tentadas == nil {
		a.tentadas = map[string]time.Time{}
	}
}

// agendarFoto põe a conversa na fila da foto de perfil quando falta (ou venceu). Devolve true se achou uma já guardada.
func (a *ajudante) agendarFoto(c Conversa) bool {
	arq := arquivoDaFoto(c.ID)
	if info, err := os.Stat(filepath.Join(a.pasta, "fotos", arq)); err == nil {
		achou := c.Foto != arq
		if achou {
			a.estado.Foto(c.ID, arq)
		}
		if time.Since(info.ModTime()) >= validadeFoto {
			a.enfileirarFoto(c.ID)
		}
		return achou
	}
	a.enfileirarFoto(c.ID)
	return false
}

// enfileirarFoto baixa a foto em segundo plano (limitado a vagasDeFoto ao mesmo tempo). Já na fila, adiada por falha ou
// marcada como sem foto: não faz nada.
func (a *ajudante) enfileirarFoto(id string) {
	a.mu.Lock()
	a.iniciarFotos()
	if a.emFila[id] {
		a.mu.Unlock()
		return
	}
	if t, ok := a.semFoto[id]; ok && time.Since(t) < esperaSemFoto {
		a.mu.Unlock()
		return
	}
	if ate, ok := a.tentadas["foto:"+id]; ok && time.Now().Before(ate) {
		a.mu.Unlock()
		return
	}
	a.emFila[id] = true
	a.mu.Unlock()
	go a.trabalharFoto(id)
}

func (a *ajudante) trabalharFoto(id string) {
	ctx := a.ctxFotos()
	a.vagasFoto <- struct{}{}
	defer func() { <-a.vagasFoto }()
	c, cancelar := context.WithTimeout(ctx, 2*prazoDaFoto)
	defer cancelar()
	dados, err := a.pegarFoto(c, id)

	a.mu.Lock()
	delete(a.emFila, id)
	switch {
	case err == nil:
		delete(a.falhasFoto, id)
		delete(a.tentadas, "foto:"+id)
		delete(a.semFoto, id)
	case errors.Is(err, errSemFoto):
		a.semFoto[id] = time.Now()
		delete(a.falhasFoto, id)
	default:
		n := a.falhasFoto[id]
		a.falhasFoto[id] = n + 1
		espera := esperaFalhaMin << n
		if espera > esperaFalhaMax || espera <= 0 {
			espera = esperaFalhaMax
		}
		a.tentadas["foto:"+id] = time.Now().Add(espera)
	}
	nenhuma := errors.Is(err, errSemFoto)
	a.mu.Unlock()

	if err == nil {
		if guardarArquivo(filepath.Join(a.pasta, "fotos"), arquivoDaFoto(id), dados) == nil {
			a.estado.Foto(id, arquivoDaFoto(id))
			a.marcarSujo()
		}
	} else if nenhuma {
		a.gravarSemFoto()
	}
}

func (a *ajudante) gravarSemFoto() {
	if a.pasta == "" {
		return
	}
	gravandoSemFoto.Lock()
	defer gravandoSemFoto.Unlock()
	a.mu.Lock()
	m := make(map[string]int64, len(a.semFoto))
	for id, t := range a.semFoto {
		m[id] = t.Unix()
	}
	a.mu.Unlock()
	if b, err := json.Marshal(m); err == nil {
		_ = guardarArquivo(filepath.Join(a.pasta, "fotos"), arquivoSemFoto, b)
	}
}

// ctxFotos é o contexto do ajudante (o teste não define: vale o de fundo).
func (a *ajudante) ctxFotos() context.Context {
	if a.ctxGeral != nil {
		return a.ctxGeral
	}
	return context.Background()
}

// baixarMiniatura pede a miniatura (Preview) da foto de perfil e baixa. errSemFoto quando a pessoa não tem foto ou
// não deixa ver: isso não é falha, é resposta.
func (a *ajudante) baixarMiniatura(ctx context.Context, cliente *http.Client, id string) ([]byte, error) {
	j, err := types.ParseJID(id)
	if err != nil {
		return nil, errSemFoto
	}
	if a.cli == nil {
		return nil, errors.New("sem conexão")
	}
	info, err := a.cli.GetProfilePictureInfo(ctx, j, &whatsmeow.GetProfilePictureParams{Preview: true})
	if errors.Is(err, whatsmeow.ErrProfilePictureNotSet) || errors.Is(err, whatsmeow.ErrProfilePictureUnauthorized) {
		return nil, errSemFoto
	}
	if err != nil {
		return nil, err
	}
	if info == nil || info.URL == "" {
		return nil, errSemFoto
	}
	return baixarFoto(ctx, cliente, info.URL)
}
