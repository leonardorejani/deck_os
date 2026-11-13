// deck-whatsapp: ajudante do Deck que lê o WhatsApp como "aparelho conectado" (QR), com a whatsmeow.
//
// SÓ LEITURA. Este programa nunca envia mensagem, nunca marca conversa como lida e nunca anuncia
// presença. Ele só recebe o que o WhatsApp entrega a um aparelho conectado.
//
// Fala com o núcleo do Deck por linhas de JSON:
//
//	saída (stdout): {"t":"fase","fase":"iniciando|aguardando_qr|conectado|desconectado|erro|qr_expirou","detalhe":""}
//	                {"t":"qr","codigo":"..."}
//	                {"t":"conversas","lista":[{id,nome,grupo,naoLidas,ultima,arquivada,numero,foto,mensagens:[{de,texto,hora,id,tipo,unica,midia}]}]}
//	                {"t":"midia","req":"...","arquivo":"...","tipo":"image/jpeg"} ou {"t":"midia","req":"...","erro":"..."}
//	entrada (stdin): {"c":"apagar"} sai do aparelho (Logout) e apaga a sessão. Fim do stdin = o Deck fechou: sai.
//	                {"c":"midia","req":"...","chat":"...","id":"..."} baixa a foto ou o áudio de uma mensagem (até 8 MB) para a pasta midia.
//
// Nada de nome, número ou texto vai para o stderr (o log do Deck é público em relatos de erro).
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "modernc.org/sqlite"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

var saida = struct {
	sync.Mutex
	enc *json.Encoder
}{enc: json.NewEncoder(os.Stdout)}

// emitir é uma variável só para o teste poder escutar o que sai.
var emitir = func(v any) {
	if prova {
		mostrarProva(v)
		return
	}
	saida.Lock()
	defer saida.Unlock()
	_ = saida.enc.Encode(v)
}

func fase(f, detalhe string) {
	emitir(map[string]string{"t": "fase", "fase": f, "detalhe": detalhe})
}

// O arquivo "pareado" diz ao núcleo e ao script de prova que há um aparelho conectado de verdade (o sessao.db
// existe desde a primeira tentativa de QR, então não serve de prova).
func marcarPareado(pasta string, sim bool) {
	arq := filepath.Join(pasta, "pareado")
	if sim {
		_ = os.WriteFile(arq, nil, 0o600)
	} else {
		_ = os.Remove(arq)
	}
}

func eChat(j types.JID) bool {
	if j == types.StatusBroadcastJID {
		return false
	}
	return j.Server == types.DefaultUserServer || j.Server == types.HiddenUserServer || j.Server == types.GroupServer
}

type ajudante struct {
	cli    *whatsmeow.Client
	estado *Estado
	pasta  string
	sujo   chan struct{}

	mu     sync.Mutex
	grupos map[string]string // nome de grupo por JID, para não perguntar de novo
	// Quando se tentou pela última vez (e falhou) pegar o nome de um grupo ou a foto de uma conversa.
	tentadas map[string]time.Time
	// Fotos de perfil: as que já estão na fila (ou baixando), as vagas de download em paralelo, quantas falhas seguidas
	// cada uma teve e as que a pessoa esconde (guardadas no disco, sobrevivem ao reinício). Tudo nasce na 1a vez.
	emFila     map[string]bool
	vagasFoto  chan struct{}
	falhasFoto map[string]int
	semFoto    map[string]time.Time
	// pegarFoto baixa a miniatura. O teste troca a rede por um falso.
	pegarFoto func(ctx context.Context, id string) ([]byte, error)
	ctxGeral  context.Context
	// completando evita duas rodadas de completar ao mesmo tempo. completarFn existe para o teste trocar a rede.
	completando   bool
	sincronizando bool
	refazer       bool
	completarFn   func(context.Context) bool
}

// Como o aparelho aparece em "Aparelhos conectados" no WhatsApp do celular. Com o tipo "desconhecido" (o padrão da
// biblioteca) o celular escreve "Outro dispositivo".
const nomeDoAparelho = "Deck OS"

func definirAparelho() {
	n := nomeDoAparelho
	store.DeviceProps.Os = &n
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_DESKTOP.Enum()
}

func (a *ajudante) marcarSujo() {
	select {
	case a.sujo <- struct{}{}:
	default:
	}
}

// publicar manda a lista pro núcleo assim que algo muda (mensagem nova não espera) e grava no disco. Mudanças que
// chegam logo atrás se juntam na próxima, no máximo umas 4 vezes por segundo.
func (a *ajudante) publicar(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-a.sujo:
			emitir(map[string]any{"t": "conversas", "lista": a.estado.Lista()})
			_ = a.estado.Salvar()
			// Nome, número e foto das conversas da lista: depois de entregar, e fora do laço, para uma consulta
			// de rede lenta não segurar a próxima mensagem.
			a.completarEmFundo(ctx)
			select {
			case <-ctx.Done():
				return
			case <-time.After(250 * time.Millisecond):
			}
		}
	}
}

// completarEmFundo roda o completar numa goroutine, uma por vez. Se algo mudou, avisa o laço para publicar de novo.
func (a *ajudante) completarEmFundo(ctx context.Context) {
	a.mu.Lock()
	if a.completando {
		a.refazer = true
		a.mu.Unlock()
		return
	}
	a.completando = true
	fn := a.completarFn
	a.mu.Unlock()
	if fn == nil {
		fn = a.completar
	}
	go func() {
		mudou := fn(ctx)
		a.mu.Lock()
		a.completando = false
		refazer := a.refazer
		a.refazer = false
		a.mu.Unlock()
		if mudou || refazer {
			a.marcarSujo()
		}
	}()
}

const (
	esperaGrupo      = 10 * time.Minute
	esperaConsulta   = 15 * time.Second
	validadeFoto     = 24 * time.Hour
	limiteMidia      = 8 << 20
	maxArquivosMidia = 100
)

func primeiro(nomes ...string) string {
	for _, n := range nomes {
		if n = strings.TrimSpace(n); n != "" {
			return n
		}
	}
	return ""
}

// identificar descobre o nome e o telefone de uma conversa direta. O contato pode vir só com o LID: aí o telefone sai
// da tabela de LIDs (ou da dica que a mensagem trouxe), e o nome do contato salvo, do nome que a pessoa se deu
// (push name) ou, no fim, só o número.
func (a *ajudante) identificar(ctx context.Context, j, dica types.JID, push string) (nome, numero string) {
	pn := j
	if j.Server == types.HiddenUserServer {
		pn = types.EmptyJID
		if dica.Server == types.DefaultUserServer {
			pn = dica
		} else if a.cli != nil && a.cli.Store != nil && a.cli.Store.LIDs != nil {
			if p, err := a.cli.Store.LIDs.GetPNForLID(ctx, j); err == nil && !p.IsEmpty() {
				pn = p
			}
		}
	}
	if pn.Server == types.DefaultUserServer {
		numero = pn.User
	}
	var nomes []string
	if a.cli != nil && a.cli.Store != nil && a.cli.Store.Contacts != nil {
		for _, k := range []types.JID{pn, j} {
			if k.IsEmpty() {
				continue
			}
			if c, err := a.cli.Store.Contacts.GetContact(ctx, k); err == nil {
				nomes = append(nomes, c.FullName, c.FirstName, c.PushName, c.BusinessName)
			}
		}
	}
	return primeiro(append(nomes, push)...), numero
}

// nomeDeQuem é o nome de quem mandou, para mostrar em grupo: o contato, o nome que a pessoa se deu ou o número.
func (a *ajudante) nomeDeQuem(ctx context.Context, j types.JID, dica types.JID, push string) string {
	n, num := a.identificar(ctx, j, dica, push)
	return primeiro(n, formatarNumero(num))
}

// completar acha o que falta nas conversas da lista (nome, telefone, foto). Devolve true se algo mudou.
func (a *ajudante) completar(ctx context.Context) bool {
	mudou := false
	pendentes := a.estado.Pendentes()
	// As fotos entram na fila antes de qualquer consulta de nome: descobrir o nome de um grupo é pedido de rede em série
	// e não pode atrasar as miniaturas da lista.
	for _, c := range pendentes {
		if a.agendarFoto(c) {
			mudou = true
		}
	}
	if a.cli == nil {
		return mudou
	}
	for _, c := range pendentes {
		if ctx.Err() != nil {
			return mudou
		}
		j, err := types.ParseJID(c.ID)
		if err != nil {
			continue
		}
		if c.Grupo || j.Server == types.GroupServer {
			if strings.TrimSpace(c.Nome) == "" {
				if n := a.nomeDoGrupo(ctx, j, true); n != "" {
					a.estado.Nome(c.ID, n)
					mudou = true
				}
			}
		} else {
			nome, numero := a.identificar(ctx, j, types.EmptyJID, "")
			if numero != "" && numero != c.Numero {
				a.estado.Numero(c.ID, numero)
				mudou = true
			}
			if nome != "" && nome != c.Nome {
				a.estado.Nome(c.ID, nome)
				mudou = true
			}
		}
	}
	return mudou
}

// baixarMidiaPedida atende o pedido do núcleo e responde com uma linha. Nada de nome nem texto vai para o erro.
func (a *ajudante) baixarMidiaPedida(ctx context.Context, req, chat, id string) {
	resp := map[string]string{"t": "midia", "req": req}
	m, ok := a.estado.Achar(chat, id)
	if !ok {
		resp["erro"] = "Não achei essa mensagem."
	} else {
		c, cancelar := context.WithTimeout(ctx, 40*time.Second)
		arq, tipo, err := baixarMidia(c, a.cli, filepath.Join(a.pasta, "midia"), chat, m)
		cancelar()
		if err != nil {
			resp["erro"] = err.Error()
		} else {
			resp["arquivo"], resp["tipo"] = arq, tipo
		}
	}
	emitir(resp)
}

// nomeDoGrupo devolve o nome do grupo. Sem `rede`, só olha o que já se sabe: quem recebe evento não espera a rede.
func (a *ajudante) nomeDoGrupo(ctx context.Context, j types.JID, rede bool) string {
	a.mu.Lock()
	n, ok := a.grupos[j.String()]
	falhou, tentou := a.tentadas["grupo:"+j.String()]
	a.mu.Unlock()
	if ok || !rede || a.cli == nil || (tentou && time.Since(falhou) < esperaGrupo) {
		return n
	}
	// Sem prazo próprio, uma consulta travada seguraria o completar inteiro.
	cctx, cancelar := context.WithTimeout(ctx, esperaConsulta)
	defer cancelar()
	info, err := a.cli.GetGroupInfo(cctx, j)
	a.mu.Lock()
	defer a.mu.Unlock()
	if err != nil || info.Name == "" {
		a.tentadas["grupo:"+j.String()] = time.Now()
		return ""
	}
	a.grupos[j.String()] = info.Name
	return info.Name
}

func (a *ajudante) tratar(ctx context.Context, ev any) {
	switch e := ev.(type) {
	case *events.Connected:
		fase("conectado", "")
		a.sincronizarArquivadas(ctx)
	case *events.Disconnected:
		fase("desconectado", "")
	case *events.PairSuccess:
		marcarPareado(a.pasta, true)
	case *events.LoggedOut:
		marcarPareado(a.pasta, false)
		// Sem a sessão, as conversas guardadas viram lixo de outra conta: somem do disco e da memória.
		a.estado.Limpar()
		_ = os.RemoveAll(filepath.Join(a.pasta, "fotos"))
		_ = os.RemoveAll(filepath.Join(a.pasta, "midia"))
		a.marcarSujo()
		fase("erro", "O aparelho foi desconectado pelo WhatsApp. Gere um QR novo.")
	case *events.UnarchiveChatsSetting:
		if e.Action != nil {
			a.estado.DesarquivaComMensagem(e.Action.GetUnarchiveChats())
			a.marcarSujo()
		}
	case *events.Mute:
		if e.Action != nil {
			a.estado.Silenciar(e.JID.String(), fimDoSilencio(e.Action.GetMuted(), e.Action.GetMuteEndTimestamp()))
			a.marcarSujo()
		}
	case *events.StreamReplaced:
		fase("erro", "Outro programa tomou o lugar do Deck nesta conexão.")
	case *events.Message:
		a.mensagem(ctx, e)
	case *events.HistorySync:
		a.historico(ctx, e)
	case *events.Archive:
		if e.Action != nil {
			a.estado.ArquivarEm(e.JID.String(), e.Action.GetArchived(), e.Timestamp)
			a.marcarSujo()
		}
	case *events.PushName, *events.Contact:
		// Nome novo no celular ou na conta: as conversas sem nome tentam de novo.
		a.marcarSujo()
	case *events.MarkChatAsRead:
		if e.FromFullSync {
			break // o retrato inteiro do app state pode ser mais velho que as mensagens que chegaram desde então
		}
		if e.Action != nil && e.Action.GetRead() {
			a.estado.Lida(e.JID.String())
		} else {
			a.estado.MarcadaNaoLida(e.JID.String())
		}
		a.marcarSujo()
	case *events.Receipt:
		// Leitura feita em outro aparelho do próprio dono (ele leu no celular).
		if (e.Type == types.ReceiptTypeReadSelf || (e.Type == types.ReceiptTypeRead && e.IsFromMe)) && eChat(e.Chat) {
			a.estado.Lida(e.Chat.String())
			a.marcarSujo()
		}
	}
}

func (a *ajudante) mensagem(ctx context.Context, e *events.Message) {
	chat := e.Info.Chat
	if !eChat(chat) {
		return
	}
	if e.Info.IsFromMe {
		a.estado.Enviada(chat.String(), e.Info.Timestamp)
		a.marcarSujo()
		return
	}
	c, ok := Analisar(e.Message, e.IsViewOnce)
	if !ok {
		return
	}
	de := ""
	if e.Info.IsGroup {
		de = a.nomeDeQuem(ctx, e.Info.Sender, e.Info.SenderAlt, e.Info.PushName)
	}
	nome, numero, grupo := "", "", e.Info.IsGroup
	if grupo {
		nome = a.nomeDoGrupo(ctx, chat, false)
	} else {
		nome, numero = a.identificar(ctx, chat, e.Info.SenderAlt, e.Info.PushName)
	}
	a.estado.Recebida(chat.String(), nome, grupo, a.mensagemDe(c, de, e.Info.ID, e.Info.Timestamp), e.Info.Timestamp)
	a.estado.Numero(chat.String(), numero)
	a.marcarSujo()
}

// mensagemDe monta a mensagem para a lista. Visualização única nunca guarda a referência do conteúdo.
func (a *ajudante) mensagemDe(c Conteudo, de, id string, quando time.Time) Msg {
	m := Msg{De: de, Texto: c.Texto, Hora: hora(quando), ID: id, Tipo: c.Tipo, Unica: c.Unica}
	if !c.Unica && c.Ref != nil && id != "" {
		m.Midia, m.Ref = true, c.Ref
	}
	return m
}

// sincronizarArquivadas pede uma vez ao WhatsApp o retrato inteiro das conversas arquivadas (app state regular_low).
// A whatsmeow não emite esses eventos na sincronização completa a não ser que se peça, e o histórico só traz o
// campo das conversas recentes: o resto aparecia em Todas. Só marca como feito depois de dar certo.
func (a *ajudante) sincronizarArquivadas(ctx context.Context) {
	if a.cli == nil || a.pasta == "" {
		return
	}
	marca := filepath.Join(a.pasta, "arquivadas-sincronizadas-2")
	if _, err := os.Stat(marca); err == nil {
		return
	}
	a.mu.Lock()
	if a.sincronizando {
		a.mu.Unlock()
		return
	}
	a.sincronizando = true
	a.mu.Unlock()
	go func() {
		err := a.cli.FetchAppState(ctx, appstate.WAPatchRegularLow, true, false)
		a.mu.Lock()
		a.sincronizando = false
		a.mu.Unlock()
		if err == nil {
			_ = os.WriteFile(marca, nil, 0o600)
			a.marcarSujo()
		}
	}()
}

// fimDoSilencio converte o fim do silêncio do WhatsApp (segundos, ms, ou -1 para sempre) em unix ms.
// Zero quer dizer sem silêncio.
func fimDoSilencio(silenciada bool, fim int64) int64 {
	if !silenciada {
		return 0
	}
	if fim <= 0 || fim > math.MaxInt64/1000 {
		return math.MaxInt64
	}
	if fim < 100_000_000_000 {
		return fim * 1000
	}
	return fim
}

func (a *ajudante) historico(ctx context.Context, e *events.HistorySync) {
	for _, c := range e.Data.GetConversations() {
		j, err := types.ParseJID(c.GetID())
		if err != nil || !eChat(j) {
			continue
		}
		nome := c.GetDisplayName()
		if nome == "" {
			nome = c.GetName()
		}
		grupo := j.Server == types.GroupServer
		numero := ""
		if nome == "" {
			if grupo {
				nome = a.nomeDoGrupo(ctx, j, false)
			} else {
				nome, numero = a.identificar(ctx, j, types.EmptyJID, "")
			}
		} else if !grupo {
			_, numero = a.identificar(ctx, j, types.EmptyJID, "")
		}
		nao := int(c.GetUnreadCount())
		if c.GetMarkedAsUnread() && nao == 0 {
			nao = 1
		}
		var msgs []Msg
		if nao > 0 {
			msgs = a.mensagensDoHistorico(ctx, j, c.GetMessages())
		}
		a.estado.Historico(j.String(), nome, grupo, nao, time.Unix(int64(c.GetConversationTimestamp()), 0), msgs)
		a.estado.Numero(j.String(), numero)
		// Arquivada: fica fora de Todas, Contatos e Grupos e só aparece no filtro Arquivadas. Histórico sem o campo
		// não diz nada (não desarquiva).
		a.estado.Silenciar(j.String(), fimDoSilencio(c.GetMuteEndTime() > 0, int64(c.GetMuteEndTime())))
		if c.Archived != nil {
			ultima := time.Unix(int64(c.GetConversationTimestamp()), 0)
			a.estado.ArquivarEm(j.String(), c.GetArchived(), ultima)
		}
	}
	a.marcarSujo()
}

// mensagensDoHistorico pega as mensagens de outras pessoas, da mais antiga para a mais nova.
func (a *ajudante) mensagensDoHistorico(ctx context.Context, chat types.JID, lista []*waHistorySync.HistorySyncMsg) []Msg {
	type item struct {
		t int64
		m Msg
	}
	var itens []item
	for _, h := range lista {
		w := h.GetMessage()
		if w == nil || w.GetKey().GetFromMe() {
			continue
		}
		c, ok := Analisar(w.GetMessage(), false)
		if !ok {
			continue
		}
		t := int64(w.GetMessageTimestamp())
		de := ""
		if chat.Server == types.GroupServer {
			if p, err := types.ParseJID(w.GetParticipant()); err == nil {
				de = a.nomeDeQuem(ctx, p, types.EmptyJID, w.GetPushName())
			}
		}
		itens = append(itens, item{t, a.mensagemDe(c, de, w.GetKey().GetID(), time.Unix(t, 0))})
	}
	sort.Slice(itens, func(i, j int) bool { return itens[i].t < itens[j].t })
	saida := make([]Msg, len(itens))
	for i, it := range itens {
		saida[i] = it.m
	}
	return saida
}

// apagarSessao sai do aparelho e só então apaga a pasta. Se a saída falhar (sem rede, por exemplo), a pasta fica:
// apagar a sessão local sem sair deixaria o aparelho ocupando uma das 4 conexões, sem a pessoa saber.
func apagarSessao(sair func() error, pasta string) error {
	if err := sair(); err != nil {
		return err
	}
	return os.RemoveAll(pasta)
}

// sairDoAparelho faz o Logout. Sem conexão de pé, tenta conectar antes (o Logout precisa dela).
func sairDoAparelho(cli *whatsmeow.Client) error {
	if cli.Store.ID == nil {
		return nil // nunca pareou: não há aparelho para sair
	}
	if !cli.IsConnected() {
		if err := cli.Connect(); err != nil && !errors.Is(err, whatsmeow.ErrAlreadyConnected) {
			return err
		}
	}
	ctx, cancelar := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancelar()
	if err := cli.Logout(ctx); err != nil && !errors.Is(err, whatsmeow.ErrNotLoggedIn) {
		return err
	}
	return nil
}

// esperaDaTentativa: 2 s, 5 s, 10 s e depois de 30 em 30 s.
func esperaDaTentativa(n int) time.Duration {
	passos := []time.Duration{2 * time.Second, 5 * time.Second, 10 * time.Second}
	if n < len(passos) {
		return passos[n]
	}
	return 30 * time.Second
}

// conectarComTentativas conecta com sessão já guardada. Rede ainda fora na subida (o Deck abre com o Mac) não
// derruba o ajudante: ele avisa "desconectado" e tenta de novo até conectar ou o Deck fechar. A reconexão
// automática da whatsmeow só vale depois da primeira conexão, por isso a primeira é por nossa conta.
func conectarComTentativas(ctx context.Context, conectar func() error, espera func(int) time.Duration, aoFalhar func()) bool {
	for n := 0; ; n++ {
		if ctx.Err() != nil {
			return false
		}
		err := conectar()
		if err == nil || errors.Is(err, whatsmeow.ErrAlreadyConnected) {
			return true
		}
		if ctx.Err() != nil {
			return false
		}
		aoFalhar()
		select {
		case <-ctx.Done():
			return false
		case <-time.After(espera(n)):
		}
	}
}

func main() {
	pasta := flag.String("pasta", "", "pasta da sessão (criada com permissão 0700)")
	flag.BoolVar(&prova, "prova", false, "escreve para uma pessoa no terminal (QR desenhado, só quantidades), em vez de JSON")
	flag.Parse()
	if *pasta == "" {
		fmt.Fprintln(os.Stderr, "uso: deck-whatsapp --pasta <pasta da sessão>")
		os.Exit(2)
	}
	if err := os.MkdirAll(*pasta, 0o700); err != nil {
		fase("erro", "Não consegui criar a pasta da sessão.")
		os.Exit(1)
	}
	_ = os.Chmod(*pasta, 0o700)

	ctx, parar := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer parar()
	encerrar = parar
	fase("iniciando", "")

	container, err := sqlstore.New(ctx, "sqlite", "file:"+filepath.Join(*pasta, "sessao.db")+"?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)", waLog.Noop)
	if err != nil {
		fase("erro", "Não consegui abrir a sessão guardada.")
		os.Exit(1)
	}
	_ = os.Chmod(filepath.Join(*pasta, "sessao.db"), 0o600)
	dev, err := container.GetFirstDevice(ctx)
	if err != nil {
		fase("erro", "Não consegui ler o aparelho guardado.")
		os.Exit(1)
	}
	definirAparelho()
	// Mídia baixada de uma execução anterior não fica no disco: só o que a pessoa pedir agora.
	_ = os.RemoveAll(filepath.Join(*pasta, "midia"))

	cli := whatsmeow.NewClient(dev, waLog.Noop)
	// Sem isto a sincronização completa do app state (a primeira, e a de arquivadas) não emite os eventos Archive.
	cli.EmitAppStateEventsOnFullSync = true
	a := &ajudante{cli: cli, estado: NovoEstado(filepath.Join(*pasta, "conversas.json")), pasta: *pasta,
		sujo: make(chan struct{}, 1), grupos: map[string]string{},
		tentadas: map[string]time.Time{}}
	a.ctxGeral = ctx
	cli.AddEventHandler(func(ev any) { a.tratar(ctx, ev) })
	go a.publicar(ctx)
	a.marcarSujo()

	// Comandos do núcleo. Fim do stdin: o Deck fechou, então este ajudante também.
	apagar := make(chan struct{}, 1)
	go func() {
		sc := bufio.NewScanner(os.Stdin)
		for sc.Scan() {
			var c struct {
				C    string `json:"c"`
				Req  string `json:"req"`
				Chat string `json:"chat"`
				ID   string `json:"id"`
			}
			if json.Unmarshal([]byte(strings.TrimSpace(sc.Text())), &c) != nil {
				continue
			}
			switch c.C {
			case "apagar":
				select {
				case apagar <- struct{}{}:
				default:
				}
			case "midia":
				go a.baixarMidiaPedida(ctx, c.Req, c.Chat, c.ID)
			}
		}
		parar()
	}()

	if cli.Store.ID == nil {
		qrs, err := cli.GetQRChannel(ctx)
		if err != nil {
			fase("erro", "Não consegui pedir o QR.")
			os.Exit(1)
		}
		if err := cli.Connect(); err != nil {
			fase("erro", "Sem conexão com o WhatsApp.")
			os.Exit(1)
		}
		go func() {
			for q := range qrs {
				switch {
				case q.Event == "code":
					fase("aguardando_qr", "")
					emitir(map[string]string{"t": "qr", "codigo": q.Code})
				case q.Event == "success":
					fase("conectado", "")
				case q.Event == whatsmeow.QRChannelTimeout.Event:
					fase("qr_expirou", "O QR expirou.")
					parar()
				case q.Event == "error":
					fase("erro", "Não consegui parear o aparelho.")
					parar()
				}
			}
		}()
	} else {
		marcarPareado(*pasta, true)
		go conectarComTentativas(ctx, cli.Connect, esperaDaTentativa, func() { fase("desconectado", "Sem conexão com o WhatsApp.") })
	}

espera:
	for {
		select {
		case <-ctx.Done():
			break espera
		case <-apagar:
			if err := apagarSessao(func() error { return sairDoAparelho(cli) }, *pasta); err != nil {
				// A pasta fica: a pessoa tenta de novo quando a rede voltar.
				fase("erro", "Não consegui sair do aparelho. Confira a internet e tente apagar de novo.")
				continue
			}
			cli.Disconnect()
			fase("desconectado", "Sessão apagada.")
			return
		}
	}
	cli.Disconnect()
	_ = a.estado.Salvar()
}
