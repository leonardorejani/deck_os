// deck-whatsapp: ajudante do Deck que lê o WhatsApp como "aparelho conectado" (QR), com a whatsmeow.
//
// SÓ LEITURA. Este programa nunca envia mensagem, nunca marca conversa como lida e nunca anuncia
// presença. Ele só recebe o que o WhatsApp entrega a um aparelho conectado.
//
// Fala com o núcleo do Deck por linhas de JSON:
//
//	saída (stdout): {"t":"fase","fase":"iniciando|aguardando_qr|conectado|desconectado|erro|qr_expirou","detalhe":""}
//	                {"t":"qr","codigo":"..."}
//	                {"t":"conversas","lista":[{id,nome,grupo,naoLidas,ultima,mensagens:[{de,texto,hora}]}]}
//	entrada (stdin): {"c":"apagar"} sai do aparelho (Logout) e apaga a sessão. Fim do stdin = o Deck fechou: sai.
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

func emitir(v any) {
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
}

func (a *ajudante) marcarSujo() {
	select {
	case a.sujo <- struct{}{}:
	default:
	}
}

// publicar manda a lista pro núcleo e grava no disco, no máximo umas 3 vezes por segundo.
func (a *ajudante) publicar(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-a.sujo:
			time.Sleep(300 * time.Millisecond)
			select {
			case <-a.sujo:
			default:
			}
			emitir(map[string]any{"t": "conversas", "lista": a.estado.Lista()})
			_ = a.estado.Salvar()
		}
	}
}

func (a *ajudante) nome(ctx context.Context, j types.JID, push string) string {
	if j.Server == types.GroupServer {
		a.mu.Lock()
		n, ok := a.grupos[j.String()]
		a.mu.Unlock()
		if ok {
			return n
		}
		if info, err := a.cli.GetGroupInfo(ctx, j); err == nil && info.Name != "" {
			a.mu.Lock()
			a.grupos[j.String()] = info.Name
			a.mu.Unlock()
			return info.Name
		}
		return ""
	}
	if c, err := a.cli.Store.Contacts.GetContact(ctx, j); err == nil {
		for _, n := range []string{c.FullName, c.FirstName, c.PushName, c.BusinessName} {
			if n != "" {
				return n
			}
		}
	}
	return push
}

func (a *ajudante) tratar(ctx context.Context, ev any) {
	switch e := ev.(type) {
	case *events.Connected:
		fase("conectado", "")
	case *events.Disconnected:
		fase("desconectado", "")
	case *events.PairSuccess:
		marcarPareado(a.pasta, true)
	case *events.LoggedOut:
		marcarPareado(a.pasta, false)
		// Sem a sessão, as conversas guardadas viram lixo de outra conta: somem do disco e da memória.
		a.estado.Limpar()
		a.marcarSujo()
		fase("erro", "O aparelho foi desconectado pelo WhatsApp. Gere um QR novo.")
	case *events.StreamReplaced:
		fase("erro", "Outro programa tomou o lugar do Deck nesta conexão.")
	case *events.Message:
		a.mensagem(ctx, e)
	case *events.HistorySync:
		a.historico(ctx, e)
	case *events.MarkChatAsRead:
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
	texto, ok := Texto(e.Message)
	if !ok {
		return
	}
	de := ""
	if e.Info.IsGroup {
		de = a.nome(ctx, e.Info.Sender, e.Info.PushName)
	}
	nome := a.nome(ctx, chat, e.Info.PushName)
	a.estado.Recebida(chat.String(), nome, e.Info.IsGroup, Msg{De: de, Texto: texto, Hora: hora(e.Info.Timestamp)}, e.Info.Timestamp)
	a.marcarSujo()
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
		if nome == "" {
			nome = a.nome(ctx, j, "")
		}
		nao := int(c.GetUnreadCount())
		if c.GetMarkedAsUnread() && nao == 0 {
			nao = 1
		}
		if c.GetArchived() {
			nao = 0
		}
		var msgs []Msg
		if nao > 0 {
			msgs = a.mensagensDoHistorico(ctx, j, c.GetMessages())
		}
		a.estado.Historico(j.String(), nome, j.Server == types.GroupServer, nao, time.Unix(int64(c.GetConversationTimestamp()), 0), msgs)
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
		texto, ok := Texto(w.GetMessage())
		if !ok {
			continue
		}
		t := int64(w.GetMessageTimestamp())
		de := ""
		if chat.Server == types.GroupServer {
			if p, err := types.ParseJID(w.GetParticipant()); err == nil {
				de = a.nome(ctx, p, w.GetPushName())
			}
		}
		itens = append(itens, item{t, Msg{De: de, Texto: texto, Hora: hora(time.Unix(t, 0))}})
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
	// É assim que o aparelho aparece em "Aparelhos conectados" no WhatsApp do celular.
	name := "Deck (só leitura)"
	store.DeviceProps.Os = &name

	cli := whatsmeow.NewClient(dev, waLog.Noop)
	a := &ajudante{cli: cli, estado: NovoEstado(filepath.Join(*pasta, "conversas.json")), pasta: *pasta,
		sujo: make(chan struct{}, 1), grupos: map[string]string{}}
	cli.AddEventHandler(func(ev any) { a.tratar(ctx, ev) })
	go a.publicar(ctx)
	a.marcarSujo()

	// Comandos do núcleo. Fim do stdin: o Deck fechou, então este ajudante também.
	apagar := make(chan struct{}, 1)
	go func() {
		sc := bufio.NewScanner(os.Stdin)
		for sc.Scan() {
			var c struct {
				C string `json:"c"`
			}
			if json.Unmarshal([]byte(strings.TrimSpace(sc.Text())), &c) == nil && c.C == "apagar" {
				select {
				case apagar <- struct{}{}:
				default:
				}
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
