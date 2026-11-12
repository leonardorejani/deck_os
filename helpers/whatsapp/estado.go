package main

import (
	"encoding/json"
	"os"
	"sort"
	"sync"
	"time"
)

// Máximo de mensagens guardadas por conversa. É o mesmo teto da leitura do banco do app.
const maxMensagens = 50

type Msg struct {
	De    string `json:"de"`
	Texto string `json:"texto"`
	Hora  string `json:"hora"`
}

type Conversa struct {
	ID        string `json:"id"`
	Nome      string `json:"nome"`
	Grupo     bool   `json:"grupo"`
	NaoLidas  int    `json:"naoLidas"`
	Ultima    string `json:"ultima"`
	Mensagens []Msg  `json:"mensagens"`
}

// Estado guarda as conversas em memória e no disco (0600, na pasta da sessão). Só entra aqui o que o
// WhatsApp mandou para este aparelho: o ajudante nunca envia nem marca nada como lido.
type Estado struct {
	mu        sync.Mutex
	conversas map[string]*Conversa
	arquivo   string
}

func NovoEstado(arquivo string) *Estado {
	e := &Estado{conversas: map[string]*Conversa{}, arquivo: arquivo}
	if arquivo == "" {
		return e
	}
	if b, err := os.ReadFile(arquivo); err == nil {
		var lista []*Conversa
		if json.Unmarshal(b, &lista) == nil {
			for _, c := range lista {
				e.conversas[c.ID] = c
			}
		}
	}
	return e
}

func hora(t time.Time) string { return t.UTC().Format(time.RFC3339) }

// Historico aplica uma conversa vinda da sincronização de histórico: o total de não lidas é o do WhatsApp.
func (e *Estado) Historico(id, nome string, grupo bool, naoLidas int, ultima time.Time, msgs []Msg) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.obter(id, nome, grupo)
	c.NaoLidas = naoLidas
	if !ultima.IsZero() {
		c.Ultima = hora(ultima)
	}
	if len(msgs) > 0 {
		c.Mensagens = aparar(msgs)
	}
}

// Recebida soma uma mensagem nova de outra pessoa.
func (e *Estado) Recebida(id, nome string, grupo bool, m Msg, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.obter(id, nome, grupo)
	c.NaoLidas++
	c.Ultima = hora(quando)
	c.Mensagens = aparar(append(c.Mensagens, m))
}

// Enviada é uma mensagem do próprio dono (do celular): quem responde leu a conversa.
func (e *Estado) Enviada(id string, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.NaoLidas = 0
		c.Ultima = hora(quando)
	}
}

// Lida zera as não lidas (leitura feita em outro aparelho).
func (e *Estado) Lida(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.NaoLidas = 0
	}
}

// MarcadaNaoLida é a marcação manual de "não lida" (sem contagem real): conta como 1.
func (e *Estado) MarcadaNaoLida(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok && c.NaoLidas == 0 {
		c.NaoLidas = 1
	}
}

func (e *Estado) Nome(id, nome string) {
	if nome == "" {
		return
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.Nome = nome
	}
}

// Limpar esquece tudo, na memória e no disco. É o que acontece quando o aparelho é desconectado pelo celular:
// as conversas daquela sessão não podem sobrar para a próxima.
func (e *Estado) Limpar() {
	e.mu.Lock()
	e.conversas = map[string]*Conversa{}
	e.mu.Unlock()
	if e.arquivo != "" {
		_ = os.Remove(e.arquivo)
	}
}

func (e *Estado) Remover(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	delete(e.conversas, id)
}

func (e *Estado) obter(id, nome string, grupo bool) *Conversa {
	c, ok := e.conversas[id]
	if !ok {
		c = &Conversa{ID: id}
		e.conversas[id] = c
	}
	if nome != "" {
		c.Nome = nome
	}
	if grupo {
		c.Grupo = true
	}
	return c
}

func aparar(m []Msg) []Msg {
	if len(m) > maxMensagens {
		return append([]Msg(nil), m[len(m)-maxMensagens:]...)
	}
	return m
}

// soNaoLidas devolve a conversa só com as mensagens ainda não lidas (as últimas, da mais antiga para a mais nova).
func soNaoLidas(c *Conversa) Conversa {
	cp := *c
	n := c.NaoLidas
	if n > len(c.Mensagens) {
		n = len(c.Mensagens)
	}
	cp.Mensagens = append([]Msg{}, c.Mensagens[len(c.Mensagens)-n:]...)
	return cp
}

// Lista é o que o Deck mostra: só as conversas com não lidas, da mais nova para a mais velha, cada uma
// com as mensagens não lidas (as últimas, da mais antiga para a mais nova).
func (e *Estado) Lista() []Conversa {
	e.mu.Lock()
	defer e.mu.Unlock()
	saida := []Conversa{}
	for _, c := range e.conversas {
		if c.NaoLidas <= 0 {
			continue
		}
		saida = append(saida, soNaoLidas(c))
	}
	sort.Slice(saida, func(i, j int) bool { return saida[i].Ultima > saida[j].Ultima })
	return saida
}

// Salvar grava o estado no disco com permissão restrita (só o dono lê).
func (e *Estado) Salvar() error {
	if e.arquivo == "" {
		return nil
	}
	e.mu.Lock()
	// Só vai para o disco o que o Deck usa (as não lidas): texto de conversa já lida não fica guardado.
	lista := make([]Conversa, 0, len(e.conversas))
	for _, c := range e.conversas {
		if c.NaoLidas > 0 {
			lista = append(lista, soNaoLidas(c))
		}
	}
	b, err := json.Marshal(lista)
	e.mu.Unlock()
	if err != nil {
		return err
	}
	tmp := e.arquivo + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, e.arquivo)
}
