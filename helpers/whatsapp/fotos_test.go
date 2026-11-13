package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func ajudanteDeFotos(t *testing.T, pasta string, n int, pegar func(context.Context, string) ([]byte, error)) *ajudante {
	t.Helper()
	a := &ajudante{estado: NovoEstado(""), sujo: make(chan struct{}, 1), grupos: map[string]string{},
		tentadas: map[string]time.Time{}, pasta: pasta, pegarFoto: pegar}
	for i := 0; i < n; i++ {
		a.estado.Recebida(fmt.Sprintf("55440000%04d@s.whatsapp.net", i), "Fulano", false, Msg{Texto: "oi"}, time.Now())
	}
	return a
}

func esperar(t *testing.T, ate time.Duration, ok func() bool) {
	t.Helper()
	limite := time.Now().Add(ate)
	for time.Now().Before(limite) {
		if ok() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("passou %v e a condição não veio", ate)
}

func guardadas(a *ajudante) int {
	n := 0
	for _, c := range a.estado.Lista() {
		if c.Foto != "" {
			n++
		}
	}
	return n
}

// Antes: uma foto por vez com 400 ms de pausa entre elas, então 16 fotos de 150 ms levavam uns 9 s. Agora 4 ao mesmo
// tempo, e nunca mais que 4.
func TestFotosBaixamEmParaleloComLimite(t *testing.T) {
	var agora, pico int32
	a := ajudanteDeFotos(t, t.TempDir(), 16, func(ctx context.Context, id string) ([]byte, error) {
		v := atomic.AddInt32(&agora, 1)
		for {
			p := atomic.LoadInt32(&pico)
			if v <= p || atomic.CompareAndSwapInt32(&pico, p, v) {
				break
			}
		}
		time.Sleep(150 * time.Millisecond)
		atomic.AddInt32(&agora, -1)
		return []byte("jpg"), nil
	})
	ini := time.Now()
	a.completar(context.Background())
	esperar(t, 3*time.Second, func() bool { return guardadas(a) == 16 })
	dur := time.Since(ini)
	t.Logf("16 fotos de 150 ms cada: %v (pico de %d ao mesmo tempo)", dur.Round(time.Millisecond), pico)
	if pico < 2 || pico > vagasDeFoto {
		t.Fatalf("pico %d: deveria ser de 2 a %d", pico, vagasDeFoto)
	}
	if dur > 1500*time.Millisecond {
		t.Fatalf("demorou %v, em série seriam uns 9 s", dur)
	}
}

// Antes a fila tinha 64 lugares e o resto era descartado em silêncio (e ainda ficava 6 h sem tentar).
func TestFilaDeFotosNaoDescartaNinguem(t *testing.T) {
	a := ajudanteDeFotos(t, t.TempDir(), 150, func(ctx context.Context, id string) ([]byte, error) { return []byte("jpg"), nil })
	a.completar(context.Background())
	esperar(t, 5*time.Second, func() bool { return guardadas(a) == 150 })
}

// Quem esconde a foto não é perguntado de novo, nem depois de reiniciar o ajudante.
func TestSemFotoNaoRepeteNemDepoisDeReiniciar(t *testing.T) {
	pasta := t.TempDir()
	var chamadas int32
	pegar := func(ctx context.Context, id string) ([]byte, error) {
		atomic.AddInt32(&chamadas, 1)
		return nil, errSemFoto
	}
	a := ajudanteDeFotos(t, pasta, 3, pegar)
	a.completar(context.Background())
	esperar(t, 2*time.Second, func() bool {
		b, err := os.ReadFile(filepath.Join(pasta, "fotos", arquivoSemFoto))
		var m map[string]int64
		return err == nil && json.Unmarshal(b, &m) == nil && len(m) == 3
	})
	esperar(t, time.Second, func() bool { return atomic.LoadInt32(&chamadas) == 3 })
	a.completar(context.Background())
	time.Sleep(100 * time.Millisecond)
	if n := atomic.LoadInt32(&chamadas); n != 3 {
		t.Fatalf("perguntou de novo na mesma execução: %d chamadas", n)
	}
	b := ajudanteDeFotos(t, pasta, 3, pegar) // "reiniciou"
	b.completar(context.Background())
	time.Sleep(150 * time.Millisecond)
	if n := atomic.LoadInt32(&chamadas); n != 3 {
		t.Fatalf("perguntou de novo depois de reiniciar: %d chamadas", n)
	}
}

// Falha de rede não é "sem foto": tenta de novo logo (30 s), e não passa 6 h marcada.
func TestFalhaDeRedeNaoViraSemFotoETentaDeNovo(t *testing.T) {
	pasta := t.TempDir()
	var chamadas int32
	var mu sync.Mutex
	rede := false
	a := ajudanteDeFotos(t, pasta, 1, func(ctx context.Context, id string) ([]byte, error) {
		atomic.AddInt32(&chamadas, 1)
		mu.Lock()
		defer mu.Unlock()
		if !rede {
			return nil, errors.New("timeout")
		}
		return []byte("jpg"), nil
	})
	a.completar(context.Background())
	esperar(t, time.Second, func() bool { return atomic.LoadInt32(&chamadas) == 1 })
	time.Sleep(50 * time.Millisecond)
	a.mu.Lock()
	_, marcada := a.semFoto["55440000000"+"0@s.whatsapp.net"]
	ate := a.tentadas["foto:55440000"+"0000@s.whatsapp.net"]
	a.mu.Unlock()
	if marcada {
		t.Fatal("falha de rede foi marcada como sem foto")
	}
	if d := time.Until(ate); d <= 0 || d > time.Minute {
		t.Fatalf("a nova tentativa deveria ser em até 1 min, foi em %v", d)
	}
	mu.Lock()
	rede = true
	mu.Unlock()
	a.mu.Lock()
	a.tentadas["foto:55440000"+"0000@s.whatsapp.net"] = time.Now().Add(-time.Second)
	a.mu.Unlock()
	a.completar(context.Background())
	esperar(t, time.Second, func() bool { return guardadas(a) == 1 })
}

// Falha de rede agenda a nova tentativa sozinha: sem nenhum evento de fora, a lista é refeita quando a espera vence.
func TestFalhaDeRedeTentaDeNovoSozinha(t *testing.T) {
	antes := esperaFalhaMin
	esperaFalhaMin = 80 * time.Millisecond
	defer func() { esperaFalhaMin = antes }()
	var chamadas int32
	a := ajudanteDeFotos(t, t.TempDir(), 1, func(ctx context.Context, id string) ([]byte, error) {
		if atomic.AddInt32(&chamadas, 1) == 1 {
			return nil, errors.New("timeout")
		}
		return []byte("jpg"), nil
	})
	// O laço do ajudante: toda vez que a lista é marcada como suja, ela é refeita.
	parar := make(chan struct{})
	defer close(parar)
	go func() {
		for {
			select {
			case <-a.sujo:
				a.completar(context.Background())
			case <-parar:
				return
			}
		}
	}()
	a.completar(context.Background())
	esperar(t, 3*time.Second, func() bool { return guardadas(a) == 1 })
	if n := atomic.LoadInt32(&chamadas); n != 2 {
		t.Fatalf("esperava 2 chamadas (falha e nova tentativa), foram %d", n)
	}
}
