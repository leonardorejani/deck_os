package main

import (
	"bytes"
	"encoding/json"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

// Máximo de mensagens guardadas por conversa. É o mesmo teto da leitura do banco do app.
const maxMensagens = 50

type Msg struct {
	De    string `json:"de"`
	Texto string `json:"texto"`
	Hora  string `json:"hora"`
	// ID da mensagem no WhatsApp: com ele o núcleo pede a mídia sob demanda.
	ID string `json:"id,omitempty"`
	// Tipo: "foto", "audio" ou "video". Vazio é texto ou outro tipo.
	Tipo string `json:"tipo,omitempty"`
	// Unica: visualização única. Nunca guarda nem entrega o conteúdo.
	Unica bool `json:"unica,omitempty"`
	// Midia: dá para baixar sob demanda (foto e áudio comuns).
	Midia bool `json:"midia,omitempty"`
	// Ref é a mídia para o download. Fica só no disco desta sessão, nunca vai para o núcleo.
	Ref []byte `json:"ref,omitempty"`
}

type Conversa struct {
	ID        string `json:"id"`
	Nome      string `json:"nome"`
	Grupo     bool   `json:"grupo"`
	NaoLidas  int    `json:"naoLidas"`
	Ultima    string `json:"ultima"`
	Mensagens []Msg  `json:"mensagens"`
	// Arquivada: o Deck só mostra no filtro Arquivadas, e não entra na conta das não lidas.
	Arquivada bool `json:"arquivada,omitempty"`
	// Numero: só os dígitos do telefone (conversa direta). Serve para abrir a conversa no WhatsApp Web.
	Numero string `json:"numero,omitempty"`
	// Foto: nome do arquivo da foto de perfil guardada na pasta fotos (vazio = sem foto ainda).
	Foto string `json:"foto,omitempty"`
}

// Estado guarda as conversas em memória e no disco (0600, na pasta da sessão). Só entra aqui o que o
// WhatsApp mandou para este aparelho: o ajudante nunca envia nem marca nada como lido.
type Estado struct {
	mu        sync.Mutex
	conversas map[string]*Conversa
	arquivo   string
	// arquivadas lembra quais conversas o WhatsApp arquivou, mesmo as sem não lidas (que não vão para o conversas.json).
	// Sem isso, a mensagem nova de uma arquivada nascia como conversa comum e furava Todas e o total.
	arquivadas    map[string]bool
	gravadasAntes []byte
}

func NovoEstado(arquivo string) *Estado {
	e := &Estado{conversas: map[string]*Conversa{}, arquivo: arquivo, arquivadas: map[string]bool{}}
	if arquivo == "" {
		return e
	}
	if b, err := os.ReadFile(arquivo + ".arquivadas"); err == nil {
		var ids []string
		if json.Unmarshal(b, &ids) == nil {
			for _, id := range ids {
				e.arquivadas[id] = true
			}
			e.gravadasAntes = b
		}
	}
	if b, err := os.ReadFile(arquivo); err == nil {
		var lista []*Conversa
		if json.Unmarshal(b, &lista) == nil {
			for _, c := range lista {
				e.conversas[c.ID] = c
				if c.Arquivada {
					e.arquivadas[c.ID] = true
				}
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
	e.arquivadas = map[string]bool{}
	e.gravadasAntes = nil
	e.mu.Unlock()
	if e.arquivo != "" {
		_ = os.Remove(e.arquivo)
		_ = os.Remove(e.arquivo + ".arquivadas")
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
		c = &Conversa{ID: id, Arquivada: e.arquivadas[id]}
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
// com as mensagens não lidas (as últimas, da mais antiga para a mais nova). Conversa sem nome mostra o número
// (nunca uma linha em branco), e a referência da mídia fica aqui dentro.
func (e *Estado) Lista() []Conversa {
	e.mu.Lock()
	defer e.mu.Unlock()
	saida := []Conversa{}
	for _, c := range e.conversas {
		if c.NaoLidas <= 0 {
			continue
		}
		cp := soNaoLidas(c)
		if strings.TrimSpace(cp.Nome) == "" {
			cp.Nome = formatarNumero(cp.Numero)
		}
		for i := range cp.Mensagens {
			cp.Mensagens[i].Ref = nil
		}
		saida = append(saida, cp)
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
	ids := make([]string, 0, len(e.arquivadas))
	for id := range e.arquivadas {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	arq, errArq := json.Marshal(ids)
	igual := bytes.Equal(arq, e.gravadasAntes)
	e.mu.Unlock()
	if err != nil {
		return err
	}
	if errArq == nil && !igual {
		if os.WriteFile(e.arquivo+".arquivadas", arq, 0o600) == nil {
			e.mu.Lock()
			e.gravadasAntes = arq
			e.mu.Unlock()
		}
	}
	tmp := e.arquivo + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, e.arquivo)
}

// Arquivar marca ou desmarca a conversa como arquivada (o WhatsApp avisa por evento).
func (e *Estado) Arquivar(id string, sim bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if sim {
		e.arquivadas[id] = true
		e.obter(id, "", false).Arquivada = true
		return
	}
	// Desarquivar conversa que nunca vimos não cria linha vazia (o app state manda isso para todas as conversas comuns).
	delete(e.arquivadas, id)
	if c, ok := e.conversas[id]; ok {
		c.Arquivada = false
	}
}

// Numero guarda os dígitos do telefone da conversa, quando se descobre.
func (e *Estado) Numero(id, numero string) {
	if numero == "" {
		return
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.Numero = numero
	}
}

// Foto guarda o arquivo da foto de perfil.
func (e *Estado) Foto(id, arquivo string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.Foto = arquivo
	}
}

// Achar devolve uma mensagem da conversa pelo id (com a referência da mídia).
func (e *Estado) Achar(chat, id string) (Msg, bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[chat]; ok && id != "" {
		for _, m := range c.Mensagens {
			if m.ID == id {
				return m, true
			}
		}
	}
	return Msg{}, false
}

// Pendentes são as conversas da lista que ainda precisam de nome, número ou foto.
func (e *Estado) Pendentes() []Conversa {
	e.mu.Lock()
	defer e.mu.Unlock()
	var r []Conversa
	for _, c := range e.conversas {
		if c.NaoLidas > 0 {
			r = append(r, Conversa{ID: c.ID, Nome: c.Nome, Grupo: c.Grupo, Numero: c.Numero, Foto: c.Foto})
		}
	}
	return r
}
