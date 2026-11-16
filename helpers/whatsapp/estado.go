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
	// Minha: a mensagem é do próprio dono. Só viaja dentro do ajudante (quem sai é Conversa.UltimaMinha).
	Minha bool `json:"-"`
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
	// Fixada e Silenciada só saem na lista (vêm dos mapas do Estado, nunca do disco da conversa).
	Fixada     bool `json:"fixada,omitempty"`
	Silenciada bool `json:"silenciada,omitempty"`
	// Previa é a última mensagem da conversa, de quem for (a do dono inclusive), sem a mídia: é o que a linha de uma
	// conversa lida mostra. Só texto curto, para o disco ficar enxuto.
	Previa *Msg `json:"previa,omitempty"`
	// UltimaMinha: a última mensagem da conversa é do dono (já respondeu). O Deck tira a conversa de Todas até o
	// contato escrever de novo, e a mensagem nova do contato desliga a marca.
	UltimaMinha bool `json:"ultimaMinha,omitempty"`
}

// maxRecentes é quantas conversas (as mais recentes) a lista leva. As com não lidas entram sempre.
const maxRecentes = 200

// maxPrevia é o tamanho do texto da prévia, em letras.
const maxPrevia = 140

// Estado guarda as conversas em memória e no disco (0600, na pasta da sessão). Só entra aqui o que o
// WhatsApp mandou para este aparelho: o ajudante nunca envia nem marca nada como lido.
type Estado struct {
	mu        sync.Mutex
	conversas map[string]*Conversa
	arquivo   string
	// arquivadas lembra quais conversas o WhatsApp arquivou, mesmo as sem não lidas (que não vão para o conversas.json).
	// Sem isso, a mensagem nova de uma arquivada nascia como conversa comum e furava Todas e o total.
	// O valor é o instante (unix ms) em que o WhatsApp arquivou, ou 0 quando só se sabe que está arquivada (marca antiga).
	arquivadas    map[string]int64
	gravadasAntes []byte
	// desarquivaComMensagem só fica ligado quando o WhatsApp avisou, explicitamente, que o ajuste "Manter conversas
	// arquivadas" está desligado (UnarchiveChatsSetting). Sem esse aviso o padrão é MANTER arquivada: o padrão atual
	// do WhatsApp é manter, e desarquivar por palpite jogava grupos arquivados no celular dentro de Todas.
	desarquivaComMensagem bool
	// silenciadas guarda até quando (unix ms) cada conversa está silenciada. Arquivada e silenciada continua
	// arquivada com mensagem nova, mesmo com "manter arquivadas" desligado.
	silenciadas map[string]int64
	// fixadas são as conversas fixadas no topo do WhatsApp.
	fixadas map[string]bool
	// recentesAntes é o último recentes.json gravado (não regrava igual).
	recentesAntes []byte
}

// arqFormato é o que vai em conversas.json.arquivadas. Antes era só a lista de ids (ainda se lê).
type arqFormato struct {
	Ids                   map[string]int64 `json:"ids"`
	DesarquivaComMensagem bool             `json:"desarquivaComMensagem,omitempty"`
	Silenciadas           map[string]int64 `json:"silenciadas,omitempty"`
	Fixadas               map[string]bool  `json:"fixadas,omitempty"`
}

func NovoEstado(arquivo string) *Estado {
	e := &Estado{conversas: map[string]*Conversa{}, arquivo: arquivo, arquivadas: map[string]int64{}, silenciadas: map[string]int64{}, fixadas: map[string]bool{}}
	if arquivo == "" {
		return e
	}
	if b, err := os.ReadFile(arquivo + ".arquivadas"); err == nil {
		var ids []string
		var f arqFormato
		if json.Unmarshal(b, &ids) == nil {
			for _, id := range ids {
				e.arquivadas[id] = 0
			}
			e.gravadasAntes = b
		} else if json.Unmarshal(b, &f) == nil {
			for id, ts := range f.Ids {
				e.arquivadas[id] = ts
			}
			e.desarquivaComMensagem = f.DesarquivaComMensagem
			for id, ate := range f.Silenciadas {
				e.silenciadas[id] = ate
			}
			for id, sim := range f.Fixadas {
				if sim {
					e.fixadas[id] = true
				}
			}
			e.gravadasAntes = b
		}
	}
	if b, err := os.ReadFile(arquivo); err == nil {
		var lista []*Conversa
		if json.Unmarshal(b, &lista) == nil {
			for _, c := range lista {
				e.conversas[c.ID] = c
				if _, ok := e.arquivadas[c.ID]; !ok && c.Arquivada {
					e.arquivadas[c.ID] = 0
				}
			}
		}
	}
	// As conversas lidas (só a prévia). Não pisam numa conversa que já veio do conversas.json.
	if b, err := os.ReadFile(arquivo + ".recentes"); err == nil {
		var lista []*Conversa
		if json.Unmarshal(b, &lista) == nil {
			for _, c := range lista {
				if _, ok := e.conversas[c.ID]; !ok && c.ID != "" {
					c.NaoLidas, c.Mensagens = 0, nil
					e.conversas[c.ID] = c
				}
			}
			e.recentesAntes = b
		}
	}
	return e
}

func hora(t time.Time) string { return t.UTC().Format(time.RFC3339) }

// maisNova devolve o instante mais recente entre o já gravado e o novo. Mensagem fora de ordem ou histórico
// atrasado não fazem a Ultima voltar no tempo (isso reabriria a conta de arquivada).
func maisNova(atual string, novo time.Time) string {
	if t, err := time.Parse(time.RFC3339, atual); err == nil && t.After(novo.UTC().Truncate(time.Second)) {
		return atual
	}
	return hora(novo)
}

// Historico aplica uma conversa vinda da sincronização de histórico: o total de não lidas é o do WhatsApp.
func (e *Estado) Historico(id, nome string, grupo bool, naoLidas int, ultima time.Time, msgs []Msg) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.obter(id, nome, grupo)
	// Histórico mais velho que o que já chegou ao vivo é retrato velho: não zera nem troca a não lida mais nova.
	if !c.maisNovaQue(ultima) {
		c.NaoLidas = naoLidas
		if len(msgs) > 0 {
			c.Mensagens = aparar(msgs)
		}
	}
	if !ultima.IsZero() {
		c.Ultima = maisNova(c.Ultima, ultima)
	}
}

// maisNovaQue diz se a conversa já tem uma mensagem mais nova que o instante dado (com o segundo como régua).
func (c *Conversa) maisNovaQue(t time.Time) bool {
	if t.IsZero() || t.Unix() <= 0 {
		return false
	}
	u, err := time.Parse(time.RFC3339, c.Ultima)
	return err == nil && u.Unix() > t.Unix()
}

// previaDe corta o texto da mensagem e tira a mídia: é o que fica no disco e na lista de uma conversa lida.
func previaDe(m Msg) *Msg {
	r := []rune(m.Texto)
	if len(r) > maxPrevia {
		m.Texto = string(r[:maxPrevia])
	}
	return &Msg{De: m.De, Texto: m.Texto, Hora: m.Hora, ID: m.ID, Tipo: m.Tipo, Unica: m.Unica}
}

// previa é a última mensagem conhecida: a guardada ou, num estado velho (sem prévia), a última das mensagens.
func (c *Conversa) previa() *Msg {
	if c.Previa != nil {
		return c.Previa
	}
	if n := len(c.Mensagens); n > 0 {
		return previaDe(c.Mensagens[n-1])
	}
	return nil
}

// Previa guarda a última mensagem da conversa (a do histórico). Só vale se não for mais velha que a que já se tem.
func (e *Estado) Previa(id string, m Msg) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c, ok := e.conversas[id]
	if !ok {
		return
	}
	e.guardarPrevia(c, m)
}

func (e *Estado) guardarPrevia(c *Conversa, m Msg) {
	if c.Previa != nil && c.Previa.Hora > m.Hora && c.Previa.ID != m.ID {
		return
	}
	c.Previa = previaDe(m)
	c.UltimaMinha = m.Minha
}

// Recebida soma uma mensagem nova de outra pessoa.
func (e *Estado) Recebida(id, nome string, grupo bool, m Msg, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.obter(id, nome, grupo)
	// A mesma mensagem de novo (o histórico já a contou, ou a que não abriu chegou aberta depois): troca, não soma.
	if m.ID != "" {
		for i := range c.Mensagens {
			if c.Mensagens[i].ID == m.ID {
				c.Mensagens[i] = m
				e.guardarPrevia(c, m)
				return
			}
		}
	}
	c.NaoLidas++
	c.Ultima = maisNova(c.Ultima, quando)
	c.Mensagens = aparar(append(c.Mensagens, m))
	e.guardarPrevia(c, m)
}

// Enviada é uma mensagem do próprio dono (do celular): quem responde leu a conversa.
func (e *Estado) Enviada(id string, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.NaoLidas = 0
		if !c.maisNovaQue(quando) {
			c.UltimaMinha = true
		}
		c.Ultima = maisNova(c.Ultima, quando)
	}
}

// EnviadaMsg é a mensagem do próprio dono (escrita no celular): zera as não lidas e vira a prévia da conversa,
// que passa a existir aqui mesmo se nunca tinha aparecido.
func (e *Estado) EnviadaMsg(id, nome string, grupo bool, m Msg, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	c := e.obter(id, nome, grupo)
	c.NaoLidas = 0
	c.Ultima = maisNova(c.Ultima, quando)
	m.Minha = true
	e.guardarPrevia(c, m)
}

// Lida zera as não lidas (leitura feita em outro aparelho).
func (e *Estado) Lida(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok {
		c.NaoLidas = 0
	}
}

// LidaEm zera só se a leitura aconteceu depois da última mensagem. Recibo ou marcação atrasada (a fila que chega quando o
// ajudante volta a conectar) é de uma leitura antiga e não pode apagar a mensagem que veio depois dela.
func (e *Estado) LidaEm(id string, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if c, ok := e.conversas[id]; ok && !c.maisNovaQue(quando) {
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
	e.arquivadas = map[string]int64{}
	e.desarquivaComMensagem = false
	e.silenciadas = map[string]int64{}
	e.fixadas = map[string]bool{}
	e.gravadasAntes, e.recentesAntes = nil, nil
	e.mu.Unlock()
	if e.arquivo != "" {
		_ = os.Remove(e.arquivo)
		_ = os.Remove(e.arquivo + ".arquivadas")
		_ = os.Remove(e.arquivo + ".recentes")
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

// Lista é o que o Deck mostra de não lidas: só as conversas com não lidas, da mais nova para a mais velha, cada uma
// com as mensagens não lidas (as últimas, da mais antiga para a mais nova). Conversa sem nome mostra o número
// (nunca uma linha em branco), e a referência da mídia fica aqui dentro.
func (e *Estado) Lista() []Conversa { return e.montar(true) }

// Recentes é o que sai para o Deck: as conversas mais recentes (até maxRecentes, mais as que têm não lidas), lidas ou
// não, da última mensagem mais nova para a mais velha. A com não lidas leva as mensagens não lidas, a lida leva só a
// prévia da última mensagem (em mensagens, com um item).
func (e *Estado) Recentes() []Conversa { return e.montar(false) }

func (e *Estado) montar(soComNaoLidas bool) []Conversa {
	e.mu.Lock()
	defer e.mu.Unlock()
	saida := []Conversa{}
	agora := time.Now().UnixMilli()
	for _, c := range e.conversas {
		var cp Conversa
		switch {
		case c.NaoLidas > 0:
			cp = soNaoLidas(c)
		case soComNaoLidas || c.previa() == nil:
			continue
		default:
			cp = *c
			cp.Mensagens = []Msg{*c.previa()}
		}
		cp.Previa = nil
		cp.Arquivada = e.arquivadaAgora(c)
		cp.Fixada = e.fixadas[c.ID]
		cp.Silenciada = e.silenciadas[c.ID] > agora
		if strings.TrimSpace(cp.Nome) == "" {
			cp.Nome = formatarNumero(cp.Numero)
		}
		if cp.Ultima == "" && c.previa() != nil {
			cp.Ultima = c.previa().Hora
		}
		for i := range cp.Mensagens {
			cp.Mensagens[i].Ref = nil
		}
		saida = append(saida, cp)
	}
	sort.Slice(saida, func(i, j int) bool { return saida[i].Ultima > saida[j].Ultima })
	if soComNaoLidas || len(saida) <= maxRecentes {
		return saida
	}
	// Só as maxRecentes mais novas, e as com não lidas ficam sempre.
	corte := saida[:0:0]
	for i, c := range saida {
		if i < maxRecentes || c.NaoLidas > 0 {
			corte = append(corte, c)
		}
	}
	return corte
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
			cp := soNaoLidas(c)
			cp.Arquivada = e.arquivadaAgora(c)
			lista = append(lista, cp)
		}
	}
	b, err := json.Marshal(lista)
	ids := make(map[string]int64, len(e.arquivadas))
	for id, ts := range e.arquivadas {
		ids[id] = ts
	}
	arq, errArq := json.Marshal(arqFormato{Ids: ids, DesarquivaComMensagem: e.desarquivaComMensagem, Silenciadas: e.silenciadas, Fixadas: e.fixadas})
	igual := bytes.Equal(arq, e.gravadasAntes)
	// As lidas vão só com a prévia (sem mensagens nem mídia): as maxRecentes mais novas. Nome, número e foto seguem.
	lidas := make([]*Conversa, 0, len(e.conversas))
	for _, c := range e.conversas {
		if c.NaoLidas <= 0 && c.previa() != nil {
			lidas = append(lidas, &Conversa{ID: c.ID, Nome: c.Nome, Grupo: c.Grupo, Ultima: c.Ultima, Numero: c.Numero, Foto: c.Foto, Previa: previaDe(*c.previa())})
		}
	}
	sort.Slice(lidas, func(i, j int) bool { return lidas[i].Ultima > lidas[j].Ultima })
	if len(lidas) > maxRecentes {
		lidas = lidas[:maxRecentes]
	}
	rec, errRec := json.Marshal(lidas)
	recIgual := bytes.Equal(rec, e.recentesAntes)
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
	if errRec == nil && !recIgual {
		if os.WriteFile(e.arquivo+".recentes", rec, 0o600) == nil {
			e.mu.Lock()
			e.recentesAntes = rec
			e.mu.Unlock()
		}
	}
	tmp := e.arquivo + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, e.arquivo)
}

// Arquivar marca ou desmarca a conversa como arquivada, no instante do aviso do WhatsApp (zero = agora).
func (e *Estado) Arquivar(id string, sim bool) { e.ArquivarEm(id, sim, time.Time{}) }

func (e *Estado) ArquivarEm(id string, sim bool, quando time.Time) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if sim {
		if quando.IsZero() {
			quando = time.Now()
		}
		e.arquivadas[id] = quando.UnixMilli()
		return
	}
	// Desarquivar conversa que nunca vimos não cria linha vazia (o app state manda isso para todas as conversas comuns).
	delete(e.arquivadas, id)
}

// Fixar marca ou desmarca a conversa como fixada no topo.
func (e *Estado) Fixar(id string, sim bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if sim {
		e.fixadas[id] = true
		return
	}
	delete(e.fixadas, id)
}

// DesarquivaComMensagem guarda o ajuste do WhatsApp (o evento UnarchiveChatsSetting): true quer dizer que
// mensagem nova desarquiva a conversa. Só o aviso explícito liga isto.
func (e *Estado) DesarquivaComMensagem(sim bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.desarquivaComMensagem = sim
}

// Silenciar guarda o silêncio da conversa até o instante dado (unix ms). Zero ou negativo tira o silêncio.
func (e *Estado) Silenciar(id string, ate int64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if ate <= 0 {
		delete(e.silenciadas, id)
		return
	}
	e.silenciadas[id] = ate
}

// arquivadaAgora diz se a conversa continua arquivada. Ela só sai do arquivo quando o WhatsApp manda (Archive com
// archived=false ou histórico dizendo que não está arquivada). Mensagem nova só desarquiva se o ajuste
// UnarchiveChatsSetting chegou dizendo que desarquiva. Chamar com o mutex tomado.
func (e *Estado) arquivadaAgora(c *Conversa) bool {
	ts, ok := e.arquivadas[c.ID]
	if !ok {
		return false
	}
	if !e.desarquivaComMensagem || e.silenciadas[c.ID] > time.Now().UnixMilli() {
		return true
	}
	if ts == 0 {
		return c.NaoLidas <= 0
	}
	if t, err := time.Parse(time.RFC3339, c.Ultima); err == nil && t.UnixMilli() > ts {
		return false
	}
	return true
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
		if c.NaoLidas > 0 || c.previa() != nil {
			r = append(r, Conversa{ID: c.ID, Nome: c.Nome, Grupo: c.Grupo, Numero: c.Numero, Foto: c.Foto, Ultima: c.Ultima, NaoLidas: c.NaoLidas})
		}
	}
	// As não lidas primeiro, depois as mais novas: quem decide o que buscar na rede começa pelo que está à vista.
	sort.Slice(r, func(i, j int) bool {
		if (r[i].NaoLidas > 0) != (r[j].NaoLidas > 0) {
			return r[i].NaoLidas > 0
		}
		return r[i].Ultima > r[j].Ultima
	})
	return r
}
