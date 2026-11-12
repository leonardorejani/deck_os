# Deck: spec v1

Status: construído (atualizado em 11/11/2026). O núcleo e o app do Mac, o painel PWA e o app nativo do iPhone (cabo e Bluetooth)
estão feitos, com `build.sh`, `instalar-iphone.sh` e a renovação automática. A prova de cada fase está em `docs/provas/`. Falta o teste
de ponta a ponta no iPhone, que só o Leonardo faz (`docs/provas/teste-final.md`). O texto abaixo é a referência do que foi construído.

## 1. O que é

O iPhone deitado do lado do Mac, carregando, vira um painel de mesa: relógio grande, Spotify, uso
das contas de IA, sessões do Claude esperando resposta e uma grade de teclas que controlam o Mac
ou abrem painéis no próprio celular (WhatsApp, Agenda). Um app só, grátis. O código
é aberto, com licença MIT (decisão 13.11).

Por que não usar pronto: nada junta painel e teclas na mesma tela (pesquisa de 10/11/2026). O
StandBy do iOS mostra widgets mas não roda teclas. Companion, slate e MiniDeck fazem só teclas.

## 2. Direção de design (tatile)

- **Produto:** painel de mesa e de palco do Leonardo, olhado de longe e tocado de relance.
- **Caráter:** tecla física, relógio de estação, retorno de palco.
- **Mundo:** relógio de placas (Solari), mesa de som digital, Stream Deck.
- **Momentos ricos:** o dígito que vira quando o minuto muda, e a tecla que acende inteira quando a
  função está ligada.
- **Assinatura:** o LED embaixo de cada tecla.

Sempre escuro, neutros sem matiz, tokens da tatile (cor, tipo, espaço, forma, movimento). Verde só
para "ligado". Sem emoji: ícone do app do Mac ou SVG.

**Espaçamento:** a tela usa a coluna "Celular" da tatile (margem 20, respiro 16, entre seções 32,
linha 60, ícone e texto 12, entre cartões 12, título ao conteúdo 8), porque o painel deitado tem
altura de celular. O que é só do Deck (cor das placas, tamanho do ícone de tecla, raio da tela) mora
num bloco único no topo do CSS. Auditor da tatile no protótipo: 0 erros, 2 avisos legítimos (cor
do calendário vem do dado, `theme-color` é hex por regra da própria tatile).

## 3. Tela (referência: iPhone 15 Pro Max)

Deitado 932 x 430, área segura de 59 em cada lateral e 21 embaixo. Em pé 430 x 932, com 59 em
cima e 34 embaixo. Ajusta a outros iPhones pela largura, mas é desenhada e conferida no 15 Pro Max.

Tudo numa tela, sem navegação. As duas composições ficam: o Leonardo alterna nos Ajustes do Mac
(item 9a), e o iPhone só mostra.

- **A, relógio em cima:** duas linhas que cruzam as colunas. Em cima, relógio e data à esquerda e
  o Spotify à direita. Embaixo, uso da semana e sessões esperando lado a lado, com a mesma altura e
  as linhas na mesma régua (mesma letra, altura e separador). Depois, uma fileira de 6 teclas.
- **B, deck ao lado:** à esquerda relógio, data, uso de IA numa linha, Spotify e sessões. À direita
  uma grade de 3 x 3 teclas.

**Teclas sempre centralizadas, carrossel quando passam de uma página.**
- **A:** a fileira tem três partes: o carrossel de apps (5 por página), uma divisória e a tecla
  "Menu" (três linhas) isolada à direita, desde a primeira tecla. Com uma página, a divisória é uma linha fina.
  Com mais, ela vira os pontinhos, na vertical.
- **B:** a grade 3 x 3 de sempre, centralizada na coluna, com o "Menu" como última tecla da grade.
  Com mais de 9, os pontinhos aparecem numa linha própria embaixo da grade.
- Páginas separadas pelo mesmo vão das teclas (nada da página vizinha encosta nem aparece na borda).
- Nada é cortado seco ao rolar. O desfoque e a transparência de cada tecla seguem a posição dela,
  calculados a cada quadro: a que sai embaça aos poucos (até 6px) e a que entra fica nítida aos poucos.
  Nada liga ou desliga de repente. A borda tem um esmaecido fixo só na folga lateral, onde tecla
  parada não chega. Parado e encaixado, tudo nítido.
- Na B, a grade começa sempre do topo da coluna, com as teclas centralizadas na horizontal.
- Pontinhos com a animação "minhoca": o indicador estica até a próxima bolinha na primeira metade do
  arrasto e encolhe nela na segunda, seguindo o dedo.

Em pé, as duas viram uma coluna: relógio e data, uso em três cartõezinhos lado a lado, 16 abaixo da data
(ícone, conta e percentual em destaque em cima, barra embaixo), Spotify, sessões e as teclas. As teclas ficam em 3 colunas e 2 fileiras por página, com
a divisória horizontal embaixo (vira os pontinhos com mais de uma página) e o "Menu" numa seção só dele,
como um botão baixo "Menu" (ícone e rótulo), para caber na altura do 15 Pro Max sem nada vazar (medido: nada passa
da área segura com 4 ou com 12 teclas, nas duas composições).

### Blocos

| Bloco | Mostra | Toque |
|---|---|---|
| Relógio | HH:MM com placas que viram, data por extenso | abre o relógio em tela cheia (seção 5) |
| Uso da semana | uma barra por conta, com o ícone do serviço: Claude `leo`, Claude `equipe` e Codex. Só o limite semanal (o Claude não tem mais a janela de 5 h, e o Codex só registra a semana: 5.694 de 5.694 registros conferidos em 10/11/2026). Ao lado, quando aquela conta renova ("sex 14h"), porque cada conta renova num dia. Amarelo a partir de 70%, vermelho a partir de 90%, sempre com o número | nada na v1 |
| Spotify | capa, faixa, artista com o ícone do Spotify, tempo decorrido e total, anterior / tocar-pausar / próxima. Fundo com um brilho das duas cores dominantes da capa (o Mac tira as cores da arte e manda junto) | capa ou nome abre o player em tela cheia (seção 5). Botões controlam a música. **Arrastar a barra de tempo pula a música**: a área de arrasto é alta, mas fica numa linha só dela, abaixo dos botões. Nas pontas da barra, **aleatório** e **repetir** (verdes quando ligados), só quando o Mac manda o estado deles |
| Sessões esperando | com o ícone do Claude: nome, pergunta e há quanto tempo espera (amarelo depois de 1 h), das 3 mais recentes | tocar em qualquer ponto do bloco (linha ou título) abre a tela de sessões, um cartão por sessão (seção 5). A linha é pequena demais para ser um alvo separado |
| Teclas | ícone, nome, LED, selo de não lidas. Na Agenda, o horário do próximo compromisso centralizado no topo, só o texto, sem pílula. Toda tecla reserva no topo o espaço do selo, então os ícones ficam na mesma altura com ou sem selo | toque executa, segurar organiza |

**Sem música tocando:** o player sai e as sessões crescem até o topo, ocupando o lugar dele (até 7
linhas). A troca é animada: o player some encolhendo e o cartão de sessões sobe e estica (medido
antes e depois, anima só a diferença). Quando a música volta, o caminho é o inverso.

**Relógio que ocupa o espaço que sobra (11/11/2026).** Quando o bloco do lado some e a coluna ficaria com um
buraco, o relógio muda de disposição: a data em cima, as horas sobre os minutos, em duas linhas de placas que
preenchem a coluna, sem os dois pontos. Vale na A deitada sem o Uso (sem contas ou escondido) e sem player e sem
sessões, na B deitada sem Sessões (sem Uso ou sem player: empilhado. Com os dois: as placas só crescem) e em pé com
dois blocos a menos (altura que sobrou entre os blocos e as teclas). Com todos os blocos, nada muda.

**Resposta otimista (11/11/2026).** O toque muda a tela na hora e só volta se o Mac recusar, com o aviso de erro
dele: Spotify (tocar, pausar, anterior, próxima, posição, aleatório, repetir), teclas com estado (acende e apaga), perfis
e blocos escondidos ou mostrados. O laço de estado de 1 s não desfaz a mudança antes de o Mac confirmar: cada mudança
sai quando o estado dele mostra o mesmo valor, quando ele recusa, ou depois de 4 s (vale o que ele diz). Os comandos
do Spotify seguem em fila, na ordem do toque, e enquanto houver comando a caminho a intenção do último toque manda (play,
pausa, play seguidos nunca mostram o estado do meio). Salvar e Excluir tecla no editor também são otimistas: o editor
fecha e a tecla muda no toque. Se o Mac recusar, a tela volta e o editor reabre com o que a pessoa digitou, com o motivo no aviso.

Saíram: a tecla do Spotify (o player já abre o app), o cartão de agenda (virou tecla) e o indicador "Mac" do canto (desalinhava o topo, e o estado sem Mac já é a tela escura).

**Descartado pelo Leonardo (questionário de 10/11/2026):** segundos no relógio, modo noite (o brilho
se regula pelo Centro de Controle do iPhone, que funciona normalmente com o app aberto), modo
relógio de descanso, tempo restante no "Manter acordado" e esconder a tecla "Nova" (hoje "Menu").

## 4. Teclas

### Toque

Encolhe (`scale(.97)`, `--mov-rapido`) e executa. Deu certo: o LED pisca uma vez. Deu errado:
aviso curto com o motivo e o que fazer.

### Tecla ligada (ex.: manter acordado)

Tem que dar para ver do outro lado da mesa (pedido de 10/11/2026: "muito discreto"). Ligada, a
tecla fica com fundo verde escuro, anel verde de 2 px, brilho curto (cabe na folga do carrossel, sem
ser cortado) e LED largo aceso. Sem a palavra
"Ligado" (pedido de 10/11/2026: "não precisa"): o anel e o LED largo marcam mesmo sem cor. O estado vem do Mac a cada 2 s, então ligar pelo Mac
também aparece.

### Menu (tecla isolada)

Substitui a tecla "Nova" e o seletor de perfil que ficava ao lado da data (pedido de 10/11/2026, item 12
da seção 13). Toque abre uma folha pequena ancorada na tecla, para cima (ao lado quando não cabe), com
duas partes: "Nova tecla" abre o editor, e "Perfil" lista os perfis com o ativo marcado, tocar troca e
grava. Com um perfil só, a parte Perfil mostra só ele. Tocar fora fecha. No modo organizar o Menu fica
parado e tocar nele abre o editor de tecla nova, como a "Nova" fazia.

### Segurar: modo organizar

Segurar 500 ms entra no modo organizar, como a tela de início do iPhone. Enquanto segura, a tecla
afunda devagar (sem contorno: o anel azul saiu a pedido, "fica feio"). O lápis de editar fica dentro
do canto da tecla, para não ser cortado pela rolagem do carrossel:
- as teclas tremem de leve e ganham um lápis no canto (com movimento reduzido: borda tracejada);
- **arrastar** muda a tecla de lugar, e as outras abrem espaço na hora. Dá para segurar e já
  arrastar no mesmo gesto;
- **tocar** numa tecla abre o editor para trocar o app ou a ação;
- barra no topo: "Arraste para mudar de lugar, toque para trocar" e o botão Pronto. Tocar fora das
  teclas também sai.

### Editor (tela inteira)

Nome, Tipo e o campo da ação, que muda conforme o tipo:

| Tipo | Escolha | Como o Mac executa |
|---|---|---|
| App | grade com os apps instalados no Mac, com ícone (`GET /api/apps`). Escolher já define o ícone. Se o app tem ações (Mail, navegadores, Notas, Calendário...), um segundo campo deixa "Só abrir" ou escolher a ação e a conta, pasta, endereço ou dia (item 26 da seção 13) | abre ou traz para frente, ou abre naquela coisa |
| Teclado | combinação gravada (`ctrl+opt+cmd+k`) | evento de teclado (precisa de Acessibilidade) |
| Comando | linha de shell | `zsh -c` |
| Atalho | lista dos Atalhos da Apple do Mac | `shortcuts run "<nome>"` |

Mais o Ícone (para tipos que não são App). A tecla do app WhatsApp ou Calendário abre a lista no
próprio iPhone. Verde quando ligada é automático (ver 9a). Salvar, Cancelar e Excluir (exclui e oferece Desfazer por 5 s).

### Teclas que já vêm prontas

| Tecla | Tipo | Detalhe |
|---|---|---|
| Manter acordado | Tecla `ctrl+opt+cmd+k` | o atalho já configurado no Vorssaint. Ligada quando o sistema mostra "Vorssaint: keep the Mac awake" (testado em 10/11/2026) |
| WhatsApp | Painel | selo com o total de não lidas |
| Agenda | Painel | horário do próximo evento no topo (só o texto), "!" sem permissão |
| Apagar tela | Comando `pmset displaysleepnow` | - |

## 5. Painéis no iPhone

WhatsApp, Sessões, Agenda e o editor de tecla abrem em tela inteira, fundo preto, com o fechar no
canto de cima à direita. O degradê do player, tirado das cores da capa, está aprovado: fica.

### Relógio em tela cheia

Tocar no relógio ou na data abre as placas grandes e a data em fundo preto. Deitado: as quatro placas numa linha
e a data embaixo. Em pé: a data em cima e as horas sobre os minutos. Tocar em qualquer lugar (ou Escape) volta. No modo
organizar não abre.

### Player em tela cheia

Tocar na capa ou no nome da música abre o player grande: capa, faixa, artista, álbum, barra de tempo (arrasta como a
pequena), aleatório, anterior, tocar-pausar, próxima e repetir, com o brilho das cores da capa no fundo. O X fecha, e
ele fecha sozinho se o Spotify fechar. O Mac manda `album`, `repetir` e `aleatorio` no estado do Spotify e aceita
`POST /api/spotify/repetir` e `/aleatorio`, com `?v=1` (liga), `?v=0` (desliga) ou sem `v` (alterna).

**Extras (11/11/2026, item 27 da seção 13).** Embaixo dos botões, uma linha com o que o Mac de quem usa oferece, e o que não
está disponível some em vez de aparecer desligado:
- **Volume**, uma barra que se arrasta (manda no máximo 4 vezes por segundo e de novo ao soltar, sempre o último valor).
  Mexe no volume do Spotify (`volume` do estado) e, quando o Mac manda também o `volumeMac`, um botão ao lado troca a barra
  entre "Spotify" e "Mac" (a escolha fica guardada no aparelho). Sem nenhum dos dois campos, a barra não existe.
- **Curtir, aparelhos e fila**, só com o Spotify conectado (`conectado` verdadeiro no estado). Curtir acende na hora.
  Aparelhos abre uma lista por cima do player (nome, tipo em português, "Tocando aqui", o aparelho restrito desligado e a
  barra de volume do que toca agora, que vai por `alvo=aparelho`), e tocar num aparelho passa a música para ele. Fila mostra
  "Tocando agora" e as próximas, e se atualiza quando a música muda.
- **Repetir** com o Spotify conectado vira três jeitos, num botão só: desligado, a lista ou o álbum, só a música (um toque
  passa para o próximo, e o aviso diz qual ficou). Sem login segue o liga e desliga do AppleScript.

### WhatsApp: não lidas por conversa

Título com o total ("23 não lidas em 5 conversas"), filtro Todas / Contatos / Grupos e "Abrir no
Mac". Uma linha por conversa (contato ou grupo): avatar (iniciais ou ícone de grupo), nome, quem
mandou e a última mensagem, hora e quantidade. Tocar abre as mensagens não lidas daquela conversa
(com o nome de quem mandou, em grupo) e o botão "Responder no Mac". A conversa se expande em altura
e os balões entram em cascata. Abrir outra recolhe a anterior antes. Não responde pelo celular.

**Pelo WhatsApp Web (11/11/2026).** Quando a origem é o WhatsApp Web (seção 13, item 16), o navegador não
entrega a lista por conversa: a folha mostra só o total ("23 não lidas"), esconde o filtro e diz em
uma frase: "Pelo WhatsApp Web o Deck vê só o total. Para ver cada conversa, use o app do WhatsApp no Mac."
Sem aba do WhatsApp Web aberta, o título fica só "WhatsApp" e o bloco diz "WhatsApp Web fechado", com o
navegador e o endereço para abrir, em vez de "0 não lidas". "Abrir no Mac", "Responder no Mac" e a tecla do
WhatsApp trazem a aba do WhatsApp Web para a frente (ou abrem web.whatsapp.com no navegador) em vez do app.

### Agenda: o mês do StandBy e a lista por data

Tela cheia, fundo preto. À esquerda, o mês no estilo do calendário do StandBy (referência enviada
pelo Leonardo): nome do mês grande em vermelho e em caixa alta, D S T Q Q S S, fim de semana em
cinza, hoje num círculo vermelho com o número no centro exato. Dias com evento ganham um ponto
discreto embaixo do número, fora do círculo. Muda
de mês deslizando para os lados ou pelas setas ao lado do nome. O mês segue o dedo enquanto ele anda e, ao soltar, troca se
o dedo foi longe (mais de um quarto da largura) ou rápido, senão volta para o lugar. As setas têm área de toque de 44 pt.

À direita (embaixo, em pé), a lista por data a partir do dia tocado, no molde da lista do WhatsApp:
grupos "Hoje, 10 de novembro", "Quinta-feira, 12 de novembro", cada linha com hora, cor do
calendário, título, calendário e local. Tocar abre "Abrir no Calendário do Mac". Evento com link de reunião de vídeo
(Meet, Zoom ou Teams, no endereço, no local ou nas notas do evento) ganha também **Entrar na reunião**, que abre no Mac:
Meet e Teams no navegador padrão, Zoom no app do Zoom se ele estiver instalado e no navegador se não. O Mac manda o link
no `Evento` (`link`, opcional: Mac antigo não manda e o botão não aparece) e só aceita abrir `https` desses três serviços
(`POST /api/reuniao/entrar`, corpo `{"link": "https://..."}`, senão 400).

### Sessões esperando

Tela de sessões em cartões, um por sessão: nome, projeto, há quanto tempo e o começo da pergunta (3 linhas), a mais
recente primeiro (duas colunas deitado, uma em pé). Cartão com uma barra de cor na lateral (azul, amarela depois de 1 h
de espera). Tocar num cartão abre a sessão, de cima para baixo: **Pede a sua resposta** (o pedido inteiro da sessão, em
destaque), a **resposta sugerida** pela sessão quando ela tem uma (só leitura), **Abrir no Mac** e o **Contexto** (a última
mensagem da sessão, com a marcação solta limpa e a tabela em linhas). Rolagem sem barra e dois botões no rodapé:
**Dispensar** (esconde até ela mudar de novo) e **Voltar** (aos cartões, no mesmo ponto da rolagem). Se a sessão aberta for
respondida no Mac, a tela volta aos cartões e avisa. Sem link para abrir a sessão no Claude do iPhone (item 4 da seção 13),
o botão "Responder" saiu: quem responde faz isso na própria sessão, e a tela diz isso. O pedido, a sugestão e o contexto
vêm de `GET /api/sessoes` (`pedido`, `sugestao`, `contexto`, todos opcionais: Mac antigo não manda e a tela abre só com a
pergunta). O estado (`/api/estado`) leva só o resumo, sem `contexto`. O Mac mascara tokens e senhas e corta o contexto em
4 mil caracteres antes de mandar.
A sessão aberta tem **Abrir no Mac** (`POST /api/sessoes/<id>/abrir`), que traz para a frente o terminal onde ela está. O
`state.json` do job não diz em que app a sessão roda, então o Mac descobre pelo processo: a sessão em segundo plano é
acompanhada por um `claude attach <nome>` num terminal, e o app dono desse terminal é o primeiro `.app` entre os pais do
processo (Orca, Terminal, iTerm, VS Code...). No Terminal da Apple a aba certa é escolhida pelo terminal (o macOS pede a
permissão de Automação na primeira vez). Sem terminal acompanhando, abre o Terminal na pasta do projeto, e o aviso diz isso.

### Spotify: volume, aparelhos, curtir, fila e repetir

O Mac entrega o que o player precisa para abrir ao tocar na capa (o desenho do player no iPhone é outra frente). Sem login
nada muda: AppleScript para tocar, pausar, anterior, próxima, posição e volume. Com o Spotify conectado nos Ajustes do Mac,
a API do Spotify soma o resto.

| Rota | O que faz | Sem login |
|---|---|---|
| `POST /api/spotify/volume?v=0..100&alvo=spotify\|mac\|aparelho` | `spotify` (padrão) é o `sound volume` do player no Mac, `mac` é o volume de saída do Mac, `aparelho` é o do aparelho do Spotify Connect que toca agora | `spotify` e `mac` funcionam, `aparelho` dá 409 |
| `GET /api/spotify/dispositivos` | lista os aparelhos do Spotify Connect (id, nome, tipo, ativo, volume, restrito) | 409 |
| `POST /api/spotify/dispositivo?id=<id>` | passa a reprodução para o aparelho, sem mudar se estava tocando ou pausado | 409 |
| `POST /api/spotify/curtir?v=1\|0` | curte ou tira a curtida da faixa que toca (o Mac pergunta ao Spotify qual é, na hora do toque) | 409 |
| `GET /api/spotify/fila` | a faixa atual e as próximas 20 | 409 |
| `POST /api/spotify/repetir?modo=faixa\|nao\|contexto` | repete só a música, nada ou a lista, pela API. Sem `modo`, `repetir[?v=1\|0]` é o do AppleScript e funciona sem login | 409 |

O `GET /api/estado` ganha em `spotify`: `volume` e `volumeMac` (0 a 100, ausentes se o Spotify ou a saída de som não
informam, como HDMI), `conectado` e, só conectado, `curtida`, `repetirFaixa` (repetir só a música ligado) e `aparelho`. O `repetir` e o `aleatorio` de antes seguem vindo do AppleScript. O
painel esconde aparelhos, curtir, fila e repetir quando `conectado` é falso. Erros da API viram 422 com o motivo em
português (sem Premium, nenhum aparelho ativo, limite de pedidos), e 409 quando o login falta ou venceu. A API do Spotify é
lenta e tem limite, então o estado nunca espera por ela: devolve o último valor guardado e atualiza por trás a cada 5 s.

**Login (Ajustes > Este Mac > Spotify):** OAuth com PKCE, sem segredo. A pessoa cria um app grátis em
developer.spotify.com/dashboard (a conta que cria o app precisa de Spotify Premium), cola o Client ID no campo, registra em
Redirect URIs o endereço `http://127.0.0.1:4778/retorno` (o Spotify só aceita http no endereço de loopback) e clica em
Conectar. O Deck abre a porta do retorno só durante o login e só em 127.0.0.1. O Client ID e os tokens ficam no Chaveiro do
Mac (nunca no `config.json`, que o painel lê), e o token é renovado sozinho antes de vencer. Desconectar apaga os tokens e
guarda a chave. **Desde 11/11/2026 o Deck leva o Client ID dele embutido** (`ChaveSpotify.embutida`, em
`mac/Nucleo/Spotify/ChaveSpotify.swift`): a tela é só "Conectar ao Spotify", e colar a própria chave fica recolhido em
"Avançado: usar a minha própria chave do app". A chave colada vence a embutida, e um valor que não tenha 32 letras e números
vale como ausente (a tela volta ao passo a passo de criar a chave). O app do Spotify em modo de desenvolvimento só aceita as
contas que o dono adicionar em User Management (até 25): quem não estiver na lista usa a própria chave (item 29 da seção 13).

## 6. Estados (nada some em branco)

| Situação | O que aparece |
|---|---|
| Mac fora do ar | a tela fecha (fundo quase opaco com desfoque) e mostra três coisas: "Mac desconectado", uma pílula com o nome do Mac procurado ("MacBook Pro de Exemplo", o nome do computador, não o endereço) com o giro de procurando e o ícone de notebook, e uma linha: "Confira se ele está ligado e no mesmo Wi-Fi". Volta sozinha quando reconecta. Com o painel já aberto, só fecha com 3 falhas seguidas e mais de 5 s sem resposta (decisão 16 da seção 13). Não tem indicador de conexão fixo na tela |
| Spotify fechado | o player sai e as sessões ocupam o espaço (animado, item 3) |
| Spotify pausado | capa a meia luz, botão de tocar |
| Agenda sem permissão | selo "!" na tecla, e a folha explica onde liberar no Mac |
| Agenda vazia | "Nada nos próximos 30 dias" |
| Nenhuma sessão esperando | ícone do Claude, "Tudo respondido" e "Nenhuma sessão do Claude esperando você" |
| Spotify fechado e nenhuma sessão | as sessões ocupam o espaço mostrando "Tudo respondido" |
| Uso sem medição recente | barra cinza com "-" |
| Lista maior que a folha | rola sem barra de rolagem visível |
| Ação falhou | aviso curto com o motivo, 4 s |
| Carregando | nada nos primeiros 200 ms, skeleton com a forma do bloco depois disso |

## 7. De onde vem cada dado (verificado no Mac em 10/11/2026)

| Dado | Fonte | Observação |
|---|---|---|
| Agenda | EventKit (Calendário do Mac) | o macOS recusa para processo de terminal sem perguntar, por isso o Deck é um app |
| Spotify | AppleScript no Spotify | nome, artista, álbum, capa, posição, duração, `repeating` e `shuffling`, testado. Próxima da fila e repetir só a música não existem no AppleScript (precisam do login na API do Spotify) |
| Spotify, volume | AppleScript (`sound volume` do player e `output volume` do Mac) | lido junto do estado, mudado por `POST /api/spotify/volume`. Testado em 11/11/2026 lendo e devolvendo o volume sem mexer na música |
| Spotify, aparelhos, curtir, fila, repetir | API do Spotify (`api.spotify.com/v1`), com o login da pessoa | só com o Spotify conectado nos Ajustes (seção 5, "Spotify: volume...") |
| Manter acordado | atalho de teclado do Vorssaint + `pmset -g assertions` | ligar e desligar testado |
| WhatsApp | banco local do WhatsApp do Mac (`ChatStorage.sqlite`), só leitura | tem nome do contato ou grupo, não lidas, última mensagem e as mensagens. Hoje: 445 conversas, 53 com não lidas. Filtrar arquivadas e escondidas. Pode mudar com atualização do WhatsApp, então tem que falhar com aviso, nunca quebrar a tela. Origem web (11/11/2026): o total de não lidas vem do título da aba do WhatsApp Web ("(23) WhatsApp"), lido por AppleScript em Safari, Chrome, Arc, Brave ou Edge (só com a aba aberta, pede Automação na primeira vez), sem lista por conversa |
| Uso do Claude | medição da troca de contas (`~/.config/claude-account`, perfis `leo` e `equipe`) | o arquivo de medição não existe agora. Quando faltar, o Deck mede por conta própria a cada 5 min com o login de cada perfil, sem gravar token em lugar nenhum |
| Uso do Codex | `rate_limits` nos arquivos de sessão do Codex (`~/.codex/sessions`) | só a janela semanal (`window_minutes` 10080), percentual, plano e `resets_at` (quando renova). Só atualiza quando o Codex roda |
| Renovação de cada conta | `reset_7d` da medição do Claude por perfil, `resets_at` do Codex | mostrado como dia e hora ("sex 14h") |
| Cores da capa | o Mac lê a arte do Spotify e tira as duas cores dominantes | vão junto do estado do Spotify |
| Ícones | ícone do app instalado no Mac (Claude, Spotify, WhatsApp...) | Codex com o ícone oficial do app do Codex para Mac (nuvem azul com o prompt). No app de verdade, o ícone sai do app instalado. Sem ele, usa esse mesmo ícone guardado no Deck |
| Sessões esperando | `~/.claude/jobs/*/state.json` com estado `blocked` | nome, resumo da pergunta (`detail`), pedido inteiro (`needs`), resposta sugerida (`suggestedReply`), projeto e hora. O contexto é o `text` da última linha do `timeline.jsonl` da sessão, quando ela é `blocked` (o `state.json` não guarda ferramenta nem comando de permissão). Hoje há 13, algumas paradas desde outubro. Falta confirmar qual link abre a sessão no Claude do iPhone |

## 8. Instalar no iPhone

**PWA servido pelo próprio Mac. Nada fica na internet.**

- A página mora dentro do app do Mac e só existe na rede de casa (`https://<nome-do-mac>.local:4777`).
  Não tem servidor externo nem site público.
- No iPhone: abrir esse endereço no Safari, Compartilhar, "Adicionar à Tela de Início". Vira um
  ícone que abre em tela cheia, sem barra do Safari, como app.
- **HTTPS local:** o iOS só deixa a tela ficar acesa sozinha (Wake Lock) e o app abrir na hora
  mesmo com o Mac desligado (service worker) em HTTPS. Na primeira vez, o app do Mac cria um
  certificado só seu e mostra um QR. O iPhone instala o perfil e confia nele em Ajustes > Geral >
  Sobre > Ajustes de Confiança de Certificados. É um passo de um minuto, uma vez só.
- **Pareamento pela página (fase 4):** o link do QR abre uma tela com o passo a passo do certificado (Baixar
  certificado, Ajustes > Perfil Transferido > Instalar, Ajustes de Confiança de Certificados). O botão leva ao `/ca.crt` do mesmo
  endereço, nunca a um link vindo do fragmento. Ao tocar em Continuar, a página troca os 6 dígitos do QR pelo código de acesso
  (`POST /api/parear`) e entra no painel. Sem o QR (o ícone da Tela de Início guarda os dados à parte do Safari), a tela "Deck não
  pareado" tem o botão "Digitar o código do Mac".
- **Abre sem o Mac:** o service worker guarda só a casca da página. O painel abre na hora e mostra "Mac desconectado" até o Mac
  voltar. A API e o certificado nunca entram em cache.
- Precisa estar no mesmo Wi-Fi do Mac. Fora de casa não conecta (v1).

### Segunda forma: app nativo pelo Xcode

Para quem quer cabo, Bluetooth e vibração ao tocar. O painel é o mesmo (a página vai
empacotada dentro do app e roda numa WKWebView), só o canal muda: em vez de HTTPS pelo Wi-Fi, o app fala com o Mac pelo cabo
ou pelo Bluetooth e não precisa de certificado nem de Wi-Fi.

- **Instalar:** `./instalar-iphone.sh` (item 10). Funciona com a conta grátis da Apple no Xcode, sem loja e sem conta paga.
- **Pareamento:** no app, "Procurar por perto" lista os Macs com o Deck. Tocar no Mac faz os dois mostrarem o mesmo código de 6
  dígitos, e a pessoa toca em Permitir no Mac (Ajustes > Conectar iPhone). A segunda via é o cabo com um código digitado no iPhone.
- **Vencimento:** com a conta grátis o app vence em 7 dias. O Deck do Mac renova sozinho a cada 5 dias, com o iPhone no cabo ou no mesmo Wi-Fi
  (item 10). Com conta paga (US$ 99/ano) duraria um ano, mas a decisão 8 da seção 13 é não pagar.
- **O que ganha:** vibração leve ao tocar numa tecla, cabo e Bluetooth com troca automática, e o painel funcionando sem Wi-Fi.
  Widget do StandBy e Live Activity continuam fora da v1.
- **O que não muda:** a página, as teclas, os painéis e a regra "o Mac configura, o iPhone mostra".

## 9. Arquitetura

```
iPhone, PWA na Tela de Início  --Wi-Fi, HTTPS-->  Deck.app no Mac (barra de menus)
  HTML, CSS, JS puro                          servidor na porta 4777, certificado local
  pede /api/estado a cada 1 s                 EventKit, AppleScript, sqlite (WhatsApp),
  manda /api/botao/<id> no toque              CGEvent, shortcuts, zsh, leitura de jobs e uso

iPhone, app nativo (a mesma página  --cabo (usbmuxd) ou Bluetooth-->  o mesmo roteador do Deck.app
  dentro de uma WKWebView)                  os pedidos viajam em quadros, a API é a mesma
```

As duas formas falam com a mesma API e podem estar pareadas ao mesmo tempo. Os pontos abaixo valem para as duas, e os de cabo e
Bluetooth só para o app nativo.

- **Segurança:** a API exige um código de 20 letras gerado no primeiro uso, entregue pelo mesmo QR.
  Sem o código, nada executa e nada é lido. Mensagens do WhatsApp e perguntas das sessões só saem
  do Mac para quem tem o código.
- **Rodízio do código (sem parear de novo):** o código de acesso troca sozinho a cada 24 h. A config
  guarda o atual (`codigoAcesso`), quando foi criado (`codigoCriadoEm`, segundos desde 1970), o
  anterior (`codigoAnterior`) e o fim da folga dele (`anteriorValeAte`): depois da troca o anterior
  vale mais 10 min. Toda resposta autenticada (200 ou erro) leva o cabeçalho `X-Deck-Codigo-Novo` com
  o código atual quando o pedido veio com o anterior. O iPhone troca o que guarda por esse valor e
  passa a mandá-lo em `X-Deck-Codigo`. Código fora da validade: 401, e só pareando de novo. A
  comparação é em tempo constante contra os dois. A troca acontece no primeiro pedido depois dos
  24 h ou quando o app do Mac chama `Rodizio.gerarSeVencido` (`vencimento` diz quando). `revogar`
  invalida os dois na hora e gera um código que nenhum iPhone tem (todos pareiam de novo). O código
  anterior nunca sai pela API. Config antiga só com `codigoAcesso` migra: ele vira o atual, criado agora.
- **Certificado para o iPhone:** `GET /ca.crt` entrega só o certificado público do CA do Deck
  (`Content-Type: application/x-x509-ca-cert`), sem código de acesso, porque o iPhone ainda não
  confia no Deck quando o baixa. A chave do CA nunca sai do Mac. O QR de Conectar iPhone leva o
  endereço do Mac com o código de pareamento e o link do certificado no fragmento
  (`https://<mac>.local:4777/#parear=<6 dígitos>&certificado=https://<mac>.local:4777/ca.crt`), que o
  navegador não envia ao servidor.
- **Cabo (app nativo, fase 6):** o app do iPhone escuta na porta 4975 do loopback do próprio aparelho.
  O Mac enxerga o iPhone plugado pelo usbmuxd (o serviço USB do macOS) e abre a conexão por ele, sem
  rede. O mesmo roteador do HTTPS atende, e o fio leva `HttpRequisicao` e a resposta em quadros (4 bytes
  de tamanho e um JSON, cada pedido com um id). O Mac olha a cada 2 s quem está plugado e conecta de novo
  sozinho ao plugar. A segunda via de pareamento usa o mesmo fio: o Mac mostra 6 dígitos, a pessoa digita
  no iPhone e `POST /api/parear` devolve o código de acesso, que o iPhone guarda no Keychain. O cabeçalho
  `X-Deck-Codigo-Novo` (rodízio do código) volta pelo fio e a página guarda o código novo.
- **Bluetooth (app nativo, fase 7):** o Mac é o periférico e anuncia o serviço do Deck, o iPhone é a central. Escreve
  os pedidos numa característica e recebe as respostas por notificação, nos mesmos quadros do cabo (o fio de bytes
  é o mesmo, com um aperto de mão cifrado na frente: Curve25519 e ChaChaPoly, ver `docs/provas/fase-7-bluetooth.md`).
  Vazão medida: pacote de 512 bytes, 60 ms de ida e volta e uns 25 KB/s, então a capa do Spotify vai reduzida a
  200 px (JPEG) e o resto do estado cabe folgado. O pareamento principal é por aqui: o iPhone lista os Macs, os dois
  derivam os mesmos 6 dígitos (comparação numérica) e a pessoa confirma nas duas telas. Troca automática: o cabo é
  o canal em uso quando está plugado e o Bluetooth assume na hora quando ele sai, com o aviso de 3 s. Os dois ficam
  conectados ao mesmo tempo, e uma leitura que estava indo pelo cabo é repetida no Bluetooth.
- **Config:** `~/Library/Application Support/Deck/config.json` (teclas, ordem, código, porta).
  O iPhone grava com `PUT /api/config` mandando a config inteira que o GET devolve (sem código nem
  porta, que ficam sempre os do Mac). Corpo incompleto é recusado e nada muda.
- **Permissões que o Mac pede uma vez cada:** Calendário, Acessibilidade (teclas), Automação do
  Spotify e dos navegadores do WhatsApp Web, Acesso Total ao Disco (banco do WhatsApp), Bluetooth e
  Rede Local. Os Ajustes têm a seção "Acessos do Mac" com o estado real de cada um, e a barra de menus
  avisa o que foi recusado.

- **Apps do Mac e ações de tecla (item 26 da seção 13):** o editor lista os apps do Mac de quem usa e o que cada um sabe
  abrir. Tudo é descoberto no Mac, nada vem pré-configurado.
  - `GET /api/apps`: `[{ "nome": "Calendário", "valor": "Calendar", "bundle": "com.apple.iCal", "navegador": false }]`, de A a Z, lido
    de `/Applications`, `/System/Applications`, `/System/Library/CoreServices/Applications`, `~/Applications` (um nível abaixo, como
    Utilitários) e do Finder. `nome` é o que o macOS mostra, `valor` é o que vai na tecla e no `open -a`, `navegador` diz se o app abre
    http e https. App só de segundo plano não entra. A lista fica guardada 30 s no Mac.
  - `GET /api/apps/<bundle>/icone`: PNG de 64 px (`image/png`, `Cache-Control: private, max-age=86400`), com cache em disco em
    `~/Library/Caches/Deck/icones` que se renova quando o app muda. Bundle que não está na lista: 404. O id do pacote nunca vira caminho.
  - `GET /api/apps/<bundle>/acoes`: `{ "bundle": "...", "acoes": [{ "id", "nome", "entrada", "rotulo", "exemplo", "opcoes", "aviso" }] }`.
    `entrada` é `nenhuma`, `lista` (escolhe entre `opcoes`, cada uma `{ valor, nome, detalhe }`) ou `texto` (digita, `exemplo` ajuda).
    `aviso` aparece quando a lista não pôde ser lida (permissão de Automação negada, o macOS esperando o Permitir, nenhuma conta).
    O bundle `navegador-padrao` não é um app da lista: representa o navegador padrão do Mac e oferece `link` e `gmail`.
  - Ações: Mail `mail-caixa` (caixa de entrada de uma conta, lista de contas lida do Mail) e `mail-novo`. Navegadores e o navegador
    padrão `link` (endereço, só http e https, sem esquema ganha https) e `gmail` (conta pelo número do `authuser` ou pelo e-mail).
    Notas `notas-pasta` (lista de pastas). Calendário `calendario-hoje` e `calendario-dia` (AAAA-MM-DD). Apps que abrem documentos
    `abrir-arquivo` (caminho começando em `/` ou `~`, que precisa existir).
  - Na tecla: o tipo continua `app`, com `valor` o app (ou `navegador-padrao`) e o campo novo `acao: { "id": "mail-caixa", "valor": "<escolha>" }`.
    Sem `acao` a tecla só abre o app, como antes. Leitura tolerante: `acao` malformada vira vazia e a tecla só abre o app. `acao` com id
    que esta versão não conhece fica na leitura mas é recusada no PUT, e a tecla responde "Essa ação não existe nesta versão do Deck".
  - Execução segura: os scripts de AppleScript são fixos e a escolha entra como argumento separado (`on run argv`), com aspas do shell,
    nunca dentro do texto do script. Argumento começando com `-` é recusado. Os comandos `open` levam o endereço ou caminho já validado
    e escapado. Cada script roda no vigia de tempo de 10 s. A leitura de uma lista abre o Mail ou as Notas escondidos (`open -g -j`) quando
    estão fechados, e o macOS pede a Automação na hora, nunca antes. Erro `-1743` vira "O Deck não tem permissão para controlar o Mail...".

## 9a. App do Mac: onde tudo se configura

Protótipo: `prototipo/mac.html`. "Um configura o outro mostra": toda configuração mora no Mac. O
iPhone só mostra e executa, e o modo organizar dele é um atalho que grava no mesmo lugar. Funciona
como os apps de barra de menus que já usamos (Vorssaint): sem ícone no Dock, um ícone na barra de
menus e uma janela de Ajustes.

**Identidade visual (pedido de 10/11/2026: "use o mesmo design do mobile"):** menu e janela usam a
identidade do iPhone, não as cores do macOS. Fundo quase preto da tela do Deck, cartões em
`--superficie` com `--raio-card`, teclas idênticas às do celular (ícone, nome, a barrinha embaixo,
verde quando acesa), barra lateral monocromática com o item escolhido em cartão e ícone verde. Verde
só para o que está ligado ou escolhido, azul só no botão principal. Do macOS fica apenas o que é da
janela (os três botões do canto).

**Nada vem configurado (pedido de 10/11/2026).** O Deck é feito para qualquer pessoa: contas de IA,
teclas, fontes de dados, calendários, nome do Mac e iPhone saem da configuração inicial e mudam nos
Ajustes. Os dados de exemplo no protótipo são só um dos dois perfis de teste ("Exemplo, já
configurado" e "Usuário novo").

### Ícone do app

Escolhido em 10/11/2026 (versão A-3, `prototipo/icones/deck.png`): quadrado arredondado do macOS,
quase preto, com quatro teclas em grade 2x2 e a primeira acesa em verde. Usado no Dock, no Finder, na
Tela de Início do iPhone, no Sobre, na configuração inicial e nos alertas do macOS. Na barra de menus
vai o mesmo desenho em uma cor só (o macOS pede ícone de uma cor ali): quatro teclas, a primeira
cheia. As outras versões ficam em `prototipo/icones.html` para referência.

### Menu da barra

Clique no ícone abre um menu curto:

- Topo: ícone, "Deck" e o estado do iPhone (ponto verde e "iPhone de Exemplo, pelo Wi-Fi", ou
  "Nenhum iPhone pareado" com o botão "Parear um iPhone").
- Layout no iPhone: os desenhos de A (relógio em cima) e B (deck 3 x 3), troca na hora.
- Perfil no iPhone (com mais de um perfil): troca rápida, para o palco.
- Aviso em amarelo só quando a pessoa recusou algum acesso ("1 acesso recusado"), que leva à seção.
- "Ajustes..." (⌘,), que abre em "Suas teclas", e "Sair do Deck" (⌘Q). Ao sair, o iPhone mostra
  "Mac desconectado".

### Janela de Ajustes

Barra lateral com nomes no jeito do Deck, o mais usado em cima, e "Feito por Leonardo Rejani" no rodapé dela: Suas teclas, Uso das IAs | Conectar
iPhone, Acessos do Mac (sempre na lista, com o selo vermelho quando há acesso recusado) | Este Mac, Sobre o
Deck. No topo de cada seção, à direita, o estado da sincronia: "Sincronizado com o iPhone de Exemplo", que vira "Salvo. Já está no iPhone" em verde por dois segundos a cada mudança. Não existe
botão Salvar: tudo grava sozinho.

| Seção | O que tem |
|---|---|
| Este Mac | Nome deste Mac (aparece no iPhone quando o Mac sai da rede), abrir junto com o Mac, procurar atualizações (uma vez por dia) e "Refazer" a configuração inicial. Sem porta nos Ajustes: se a 4777 estiver ocupada, o menu da barra avisa e o Deck não troca de porta em silêncio. Grupo Spotify: campo da chave do app (Client ID), "Conectar" ("Cancelar" enquanto espera o navegador, "Desconectar" quando conectado), o endereço de retorno com "Copiar", "Abrir site" do desenvolvedor do Spotify e o passo a passo para criar a chave grátis |
| Suas teclas | Em cima, os perfis em abas (o que está no iPhone tem o ponto verde), "+ Perfil", o nome do perfil editável, "Usar no iPhone agora" e "Excluir perfil" (com Desfazer). Depois, as páginas do iPhone em abas, uma por vez, sem rolagem lateral (5 por página na A, 9 na B). Com uma página só, as abas somem. Arrastar reordena dentro da página, e soltar numa aba leva a tecla para o fim daquela página. "Nova" fica no fim da última página e abre a aba dela. Embaixo, o editor da tecla escolhida na largura toda (detalhe abaixo). Editar um perfil no Mac não muda o que o iPhone está mostrando |
| Uso das IAs | Painel com um cartão por conta: nome no iPhone (editável), serviço e conta, porcentagem grande da semana (amarela a partir de 70, vermelha a partir de 90), barra, quando renova ("em 3 dias", "amanhã", "hoje às 14h", com a data exata ao passar o mouse), interruptor "No iPhone" e Remover, que só aparece ao passar o mouse (Desfazer no aviso e ⌘Z). No topo, "Mais perto do limite". O cartão "Adicionar conta" abre uma janela por cima: escolhe Claude Code ou Codex, mostra as contas achadas neste Mac com "Adicionar" e, embaixo, como somar outra conta (detalhe abaixo) |
| Conectar iPhone | Aparelhos pareados (com "Desconectar") e "Parear outro iPhone": no cartão, o QR com o código curto (vale 10 minutos) e o endereço com "Copiar" ao lado. Os 3 passos (câmera, certificado, Adicionar à Tela de Início) ficam embaixo, fora do cartão, com números alinhados. O código curto é trocado pelo código longo da API no pareamento. O grupo "Parear um iPhone pelo Wi-Fi" é o do Safari (PWA) e a nota dele explica que o PWA é limitado: só com o iPhone na mesma rede do Mac, sem cabo nem Bluetooth, sem atualizar fora do Wi-Fi e com a tela podendo apagar sozinha. Acima dele, "App no iPhone, por cabo e Bluetooth": pareando, mostra o que o Mac espera em cada etapa (visível por Bluetooth, o código para conferir com Recusar e Permitir, ou o código a digitar na segunda via pelo cabo) e os passos. Pareado, mostra a versão instalada, o último canal (cabo ou Bluetooth) e a "Renovação automática": o Deck renova sozinho a cada 5 dias, com o iPhone no cabo ou no mesmo Wi-Fi (a Apple faz o app vencer em 7), e se não der tenta de novo quando o iPhone aparece no cabo ou no Wi-Fi, ou é desbloqueado. Embaixo das linhas, uma nota curta com as condições para a renovação funcionar. "Renovar agora" é a ação manual. Só quando o prazo de 7 dias aperta sem ter dado certo aparece o cartão amarelo "O app vence em 2 dias e a renovação não deu certo" (com "Tentar agora"), mais uma linha amarela no menu da barra e o selo "1" no item da barra lateral |
| Acessos do Mac | Todos os acessos que o Deck usa, cada um com o estado real lido do macOS (Liberado, Não perguntado, Recusado, ou Sem como conferir quando o macOS só responde com o app aberto): Calendários, Automação do Spotify, Automação dos navegadores (só quando o WhatsApp é lido pelo navegador), Acessibilidade, Acesso Total ao Disco, Bluetooth e Rede Local. Cada linha tem o nome que o macOS usa, o motivo embaixo ("Para o player do iPhone mostrar a música e controlar o Spotify") e "Abrir Ajustes do Sistema", que abre a página certa. Onde o macOS ainda não perguntou, "Permitir" faz o próprio Deck pedir (a janelinha do macOS aparece então, nunca antes). A lista se atualiza sozinha quando o Deck volta para a frente. Spotify não instalado e WhatsApp só pelo app tiram a linha deles |
| Sobre | Só informação do app: logo, "Deck" e a frase do produto, versão (com o número da compilação), data da atualização, o que precisa (macOS 13 ou mais novo, iOS 16.4 ou mais novo) e o que está em uso. Embaixo, o grupo "Projeto aberto" (pedido de 11/11/2026: "Adiciona infos do repositório no sobre, dar estrela, etc."): "Gostou do Deck?" em primeiro, com o botão amarelo e ícone de estrela "Dar uma estrela no GitHub" (abre a página do repositório, onde fica a estrela), Licença (MIT, abre o arquivo `LICENSE`) e "Achou um erro?" com "Relatar um problema" (abre `issues/new`). Tudo abre no navegador padrão. A assinatura fica no rodapé da barra lateral |

### Adicionar conta de IA

Janela por cima dos Ajustes, aberta pelo cartão "Adicionar conta". Em cima, Claude Code ou Codex.
Depois, "Achei neste Mac" com as contas daquele serviço que o Deck encontrou e ainda não estão no
painel, cada uma com "Adicionar" (um clique).

**Claude Code, outra conta (token colado):**
1. "Gere um token no Terminal": `claude setup-token`, com "Copiar" e "Abrir no Terminal" (abre o
   Terminal com o comando digitado). Ele abre o navegador, a pessoa entra na conta que quer
   acompanhar e copia o token.
2. "Cole o token aqui": campo de senha com "Mostrar". Ao colar, espaço e quebra de linha saem
   sozinhos (o Terminal quebra o token em linhas). O token fica no Chaveiro do Mac e só serve para
   ler o uso.
3. "Dê um nome": o que aparece no iPhone.

"Adicionar" só liga com algo colado. Erros do lado do campo, com espaço já reservado: não começa
com `sk-ant-oat01-` ("Isso não é um token do Claude Code"), curto demais ("parece cortado"), e
recusado pelo Claude na conferência ("Gere outro com claude setup-token"). Enquanto confere, o
botão diz "Conferindo...". Clicar fora com token colado não fecha (não perde o que colou). Esc fecha.

**Codex, outra conta:** "Entre na conta pelo Terminal" com `codex login` (Copiar e Abrir no
Terminal) e "Volte aqui": o Deck mostra "Esperando o login..." e a conta aparece sozinha em "Achei
neste Mac" quando o login termina. A confirmar na fase 1: como o Codex guarda mais de uma conta e
de onde sai o uso da semana de cada uma (hoje o login fica em `~/.codex`, uma conta por vez).

### Editor de tecla no Mac

Na largura toda, abaixo das páginas. No topo, a prévia da tecla como ela fica no iPhone e o nome,
editável ali mesmo no título (muda na prévia, na grade e no iPhone enquanto digita), o que ela faz em
uma linha e "Excluir tecla" (⌘Z desfaz). Embaixo, dois passos numerados:

1. **O que a tecla faz:** quatro cartões de uma linha: App (abre um app), Teclado (aperta teclas),
   Comando (roda no Terminal) e Atalho (roda um atalho do app Atalhos). Não existe tipo "tela no
   iPhone": a tecla do app WhatsApp ou Calendário abre a lista no próprio iPhone, com "Abrir no Mac"
   dentro. Config antiga com o tipo painel vira o app correspondente.
2. **A configuração do tipo**, e no fim dela o ícone (no App é sempre o do próprio app):
   - App: busca entre todos os apps da pasta Aplicativos (sem acento e sem maiúscula), com "Mais
     usados" e "Todos, de A a Z" quando a busca está vazia. Ícones grandes (52px), para reconhecer o
     app de relance.
   - Atalho: busca na lista do app Atalhos.
   - Teclado: "Clique aqui e aperte as teclas", que grava do teclado de verdade (Esc cancela, exige
     uma tecla de controle), com exemplos prontos.
   - Comando: caixa em fonte de código, "Testar agora" e comandos prontos (apagar tela, abrir
     Downloads, silenciar, esvaziar Lixeira).

**Sem campo "Acesa quando" (pedido de 10/11/2026: "o mais fácil de configurar e intuitivo
possível").** Ninguém escreve comando para a tecla ficar verde. O Deck acende sozinho o que ele
reconhece: manter o Mac acordado (qualquer app segurando o Mac acordado, lido nas assertions do
`pmset`), e outras funções conhecidas que entrarem depois. O mesmo vale para o editor do iPhone.

### Configuração inicial (primeira vez)

Janela própria, no centro da tela, com o brilho verde do Deck no topo e uma barra de progresso em
faixas. Tudo centralizado, na largura e na altura (a lista numerada do pareamento fica no centro,
mas lê da esquerda). Abre sozinha na primeira vez. Enquanto não termina, o menu da barra mostra "Continuar
configuração" no lugar da composição. "Refazer" a configuração inicial fica em Geral.

1. **Boas-vindas:** o ícone e "Seu iPhone vira um painel do Mac". Leva uns dois minutos.
2. **Conecte o iPhone:** QR com o código grande, o endereço e os três passos embaixo. "Esperando o
   iPhone..." até ele aparecer. Dá para "Fazer depois".
3. **Como o iPhone fica:** A ou B lado a lado, cada uma com a prévia de verdade da tela do iPhone
   (print do protótipo do iPhone, guardado em `prototipo/previas/`), o nome e uma linha
   dizendo onde fica cada coisa. O que aparece o Deck detecta sozinho (14.2).
4. **Suas contas de IA** (sempre): as contas achadas neste Mac, marcáveis, e "Conectar outra conta",
   que abre a mesma janela de "Adicionar conta" dos Ajustes por cima da configuração. A conta
   conectada entra na lista já marcada.
5. **Primeiras teclas:** sugestões marcáveis feitas com o que o Mac tem, 5 por linha, ocupando a
   largura.
6. **Libere os acessos:** Calendários, Automação, Acesso Total ao Disco e Acessibilidade, com o
   nome que o macOS usa e o motivo embaixo. "Permitir" abre a janelinha do macOS. Liberado vira
   "Liberado" em verde, recusado vira "Abrir Ajustes do Sistema". Nenhum é obrigatório.
7. **Pronto:** só o sinal verde, o título e uma frase, no meio. Sem lista de resumo. Ao concluir, o
   menu da barra abre sozinho mostrando onde o Deck mora. Nenhum alerta aparece depois.

O que ficou sem liberar no passo 6 ainda é pedido na hora do uso (14.1).

### Conta e compra (fase futura)

Ideia do Leonardo para quando o Deck for vendido: um onboarding mais caprichado, no estilo do Droppy,
em que a pessoa cria a conta e compra a licença. Entra na configuração inicial logo depois das
boas-vindas ("Entrar ou criar conta", depois a licença) e ganha uma seção "Conta" nos Ajustes. Não
entra agora: o Deck segue livre e de código aberto até essa decisão.

### Como o iPhone fica sabendo

O config.json é a fonte única. Cada gravação sobe um número de versão. O iPhone já pede o estado a
cada segundo: quando a versão muda, ele busca a configuração nova e se redesenha. O modo organizar
do iPhone grava pela API no mesmo arquivo, e a janela do Mac se atualiza junto. No protótipo, a
mesma coisa acontece entre as duas abas do navegador.

### Como é feito

SwiftUI: `MenuBarExtra` no estilo janela para o menu, `Settings` para a janela de Ajustes,
`LSUIElement` para não ter ícone no Dock e `SMAppService` para abrir junto com o Mac.

## 10. Distribuição

Sem App Store. O repositório é open source, com licença MIT (decisão 11 da seção 13, de 11/11/2026). O arquivo `LICENSE` está na raiz e o `README.md` e os Ajustes do Mac apontam para ele.

- **App do Mac:** um `.dmg` (hoje gerado com `./build.sh`, e a página de versões do GitHub quando o repo abrir): abre e arrasta o Deck para Aplicativos.
  Sem a conta paga de desenvolvedor (US$ 99/ano), o macOS bloqueia na primeira abertura e é preciso
  liberar em Ajustes do Sistema > Privacidade e Segurança > "Abrir mesmo assim". Com a conta, abre
  direto. Quem preferir compila com `./build.sh`, que gera `dist/Deck-1.0.dmg` (Release, assinatura local "Sign to Run
  Locally", versão 1.0 com o número da compilação) e grava onde está o repo para a renovação do app do iPhone.
- **iPhone, forma rápida:** nada para baixar, é o PWA do item 8. O README tem o passo a passo das duas formas.
- **iPhone, forma completa (app nativo):** `./instalar-iphone.sh` confere o Xcode, a conta da Apple no Xcode e o iPhone
  desbloqueado no cabo, e instala pelo `ios/instalar.sh`. Com a conta grátis o app vence em 7 dias, então o `Deck.app`
  renova sozinho a cada 5 dias contando da última instalação boa, com a mesma sequência da prova 0.4 (apaga o perfil
  guardado pelo Xcode, gera outro com `-allowProvisioningUpdates`, compila e reinstala com `devicectl`). O perfil guardado
  precisa sair porque o Xcode o reaproveita e a reinstalação não empurraria o vencimento (verificado em 10/11/2026).
  Se falhar (iPhone fora do cabo ou bloqueado, sessão da Apple ID vencida, Xcode ausente), o motivo fica guardado em
  português e o Deck olha o iPhone a cada 5 minutos (uma consulta curta ao `devicectl`, sem compilar). Voltou ao cabo ou
  foi desbloqueado, tenta de novo. Falha que não é do iPhone só repete depois de 1 hora. O cartão amarelo, o selo "1" e a
  linha no menu aparecem só 12 horas depois da hora de renovar. O Deck sabe onde está o repo por
  `~/Library/Application Support/Deck/renovacao.plist` (`pasta` e `instaladoEm`), que os dois scripts preenchem. O
  `Deck.app --renovar-agora` faz uma renovação ao abrir, para prova, e tudo vai para `~/Library/Logs/Deck/deck.log`.
  Vale o iPhone no cabo ou pareado com o Xcode pela rede (o `devicectl` o lista disponível sem cabo), só o iPhone (iPad e
  relógio ao alcance são ignorados), e nada abre janela. Como funciona e as condições: `docs/renovacao.md`.

## 11. Cuidados de painel que fica ligado

- Tela acesa com Wake Lock (precisa do HTTPS local). Sem ele, avisar para desligar o bloqueio
  automático.
- Contra queima de tela (OLED): tudo desloca 1 a 2 px a cada 3 min, como o StandBy.
- Brilho: pelo Centro de Controle do iPhone (o PWA não bloqueia). Modo noite descartado.

## 12. Plano

| Fase | Entrega | Prova |
|---|---|---|
| 0 | Esta spec e o protótipo aprovados | ok do Leonardo |
| 1 | App do Mac: servidor HTTPS, certificado e QR, código de acesso, estado (agenda, Spotify, WhatsApp, uso, sessões, LEDs), ações | testes do núcleo (HTTP, teclas, leitura do WhatsApp, jobs e uso com dados de exemplo) e `curl` em cada rota |
| 2 | Página do iPhone na composição aprovada, com todos os estados do item 6 | render em 932 x 430 e 430 x 932 no Chrome, auditor da tatile sem erro e sem valor solto |
| 3 | Modo organizar (segurar, arrastar, editor, excluir com Desfazer) e painéis (WhatsApp, Agenda, Sessões) | teste de ponta a ponta no Chrome contra o Mac de verdade, com toque simulado |
| 4 | PWA: instalar, tela cheia, Wake Lock, service worker, deslocamento anti-queima | auditor PWA da tatile, e no iPhone dele (pendente até ele testar) |
| 5 | Iniciar com o Mac, configuração inicial, README padrão, repositório no GitHub | `verificar.sh` verde e a configuração inicial feita numa conta nova do macOS |
| 6 (futura) | Conta e compra da licença no onboarding (item 9a) | decisão do Leonardo sobre venda |

`verificar.sh`: typecheck do Swift, testes do núcleo, `node --check` do JS, auditor da tatile.

## 13. Decisões (questionário de 10/11/2026)

1. Composição: as duas, alternáveis nos Ajustes do Mac.
2. Relógio: só HH:MM.
3. Noite: igual o dia todo, brilho pelo Centro de Controle.
4. "Responder": abre a sessão no app do Claude do iPhone. Sem link, mostra a pergunta inteira.
5. Cor da capa no player, quando renova por conta, tempo de espera das sessões, sessões no lugar do
   player sem música (animado), barra de tempo arrastável: sim.
6. Modo descanso, tempo restante no "Manter acordado", esconder "Nova" (hoje "Menu"): não.

Decisões do plano de implementação (`PLANO.md`, 10/11/2026):

7. iPhone em duas formas com o mesmo painel: PWA pelo Wi-Fi, para usar rápido, e app nativo
   opcional, instalado pelo Xcode, que ganha cabo e Bluetooth.
8. Sem loja e sem conta paga da Apple: "Não vou pagar pela loja só pra usar de forma pessoal". O app
   nativo usa a conta grátis, e o Deck do Mac renova a instalação sozinho a cada 5 dias.
9. Cabo e Bluetooth só no app nativo. O Safari do iPhone não alcança USB nem Bluetooth, então o PWA
   fica no Wi-Fi.
10. Nome: Deck. Nada roda na internet.
11. Open source, licença MIT (11/11/2026). Pedido do Leonardo: "Adiciona infos do repositório no sobre, dar estrela, etc. vamos deixar esse repo open source mesmo". Substitui a decisão de 10/11/2026 de manter o repositório privado por enquanto.

12. Menu no lugar da "Nova" e do seletor de perfil (10/11/2026). Pedido do Leonardo: "esse seletor de
    perfil pode ficar no mesmo botao de 'Nova'. Ao invés do Nova cria um 'Menu' onde o usuário tem 2
    opções. Trocar o perfil ou adicionar algo naquela seção". O chip de perfil sai de perto da data e a
    tecla "Nova" vira "Menu", com "Nova tecla" e "Perfil" (ver "Menu" na seção 4).

Decisões da fase 5, protótipo do app nativo (10/11/2026, `prototipo/nativo.html`):

13. Pareamento do app nativo: o caminho principal é o Bluetooth. O iPhone lista os Macs com Deck por
    perto, toca no dele e os dois mostram o mesmo código, que se confere e confirma nas duas telas. A
    segunda via é o cabo com código de 6 dígitos digitado no iPhone, num link discreto na tela de
    procurar ("Conectar pelo cabo com código"). Palavras dele: "gosto da opção B por ser mais
    intuitivo e nao precisar de cabo. mas gosto de pensar em manter a opção A como segunda tentativa
    de conexão. Tipo o whatsapp quando vai conectar por código ao invés do QR Code". Cabo com Permitir
    e sem código saiu.
14. Canal em uso: um aviso de 3 segundos ao trocar de canal, com o ícone e "Pelo cabo" ou "Pelo
    Bluetooth". Nada fica na tela (a regra de não ter indicador fixo continua). A tela "Mac
    desconectado" passa a dizer "Procurando pelo cabo e pelo Bluetooth" no app nativo. Só a tela
    escura e a folha ao tocar no relógio ficaram de fora.
15. Ajustes > Conectar iPhone ganha o grupo do app nativo, como no protótipo. Palavras dele: "Temos
    que fazer essa renovação de forma automática pro usuário". A renovação é automática, o cartão
    amarelo só aparece quando o prazo aperta, e "Renovar agora" é ação manual secundária. No Mac, o prazo aperta
    12 horas depois da hora de renovar (5 dias depois da última instalação) sem a renovação ter dado certo: até lá o Deck
    só "tenta de novo sozinho". O Mac só aceita pedido de pareamento por Bluetooth com Conectar iPhone aberto.

Decisões de 11/11/2026, ajustes de UX do app do Mac:

16. Ícone da barra para todos os usuários. Palavras dele: "isso deve estar funcionando pra outros usuários. nao
    adianta funcionar somente no meu". O macOS 26 prende o item da barra ao app do terminal que abriu o Deck por
    `open`, e o ícone some se esse app estiver desligado em Permitir na Barra de Menus (`docs/lessons/`). Nenhum script
    ou código do Deck chama `open` para abrir o Deck: `scripts/abrir-deck.sh` e `./build.sh --abrir` pedem ao Finder
    (osascript), o app nunca se relança sozinho, e o README manda abrir pelo Finder. O aviso do ícone escondido também
    diz "se abriu o Deck por um terminal, feche e abra pelo Finder". Teste: `scripts/teste/abrir-deck.test.sh`.
17. O aviso "O ícone do Deck está escondido na barra de menus" sai sozinho. Palavras dele: "isso deve sair após
    liberar". O app olhava o item uma vez, 3 segundos depois de abrir. Agora reconfere ao abrir os Ajustes, ao
    ganhar o foco e a cada 3 segundos enquanto o aviso está na tela (oclusão da janela do item e posição dentro de
    alguma tela), e para de olhar quando o ícone aparece.
18. Contas de IA. Palavras dele: "Não to conseguindo configurar as contas de IA no Deck, clico pra adicionar contas e
    nada acontece". A janela Adicionar conta era um NSHostingView pendurado dentro do NSHostingView da janela (o
    SwiftUI avisa que não é suportado) e não aparecia no macOS 26. Virou camada do próprio SwiftUI por cima da janela
    inteira. Ela acha as contas do Claude (perfis em `~/.config/claude-account/logins`) e do Codex
    (`~/.codex/auth.json`) deste Mac.

19. WhatsApp pelo navegador. O Deck lia só o banco do app do WhatsApp para o Mac, e quem usa o WhatsApp Web não
    via mensagem recente. Palavras dele: "Ele não está puxando mensagens recentes, talvez pode estar linkado
    com o app do whatsapp, mas eu utilizo o whatsapp WEB. Tem que ter essa opção no painel de selecionar o
    app ou web, ou sei lá como seria configurado isso pra já ficar mais fácil pro usuário só instalar e usar
    de boa, sem ficar configurando url. O 'Abrir no mac' deveria mandar pro whatsapp web (no meu caso), o
    usuário deve poder configurar." Decidido:
    - Config `whatsapp.origem`: `auto` (padrão), `app` ou `web`, e `whatsapp.navegador`, o navegador onde o
      WhatsApp Web abre quando não há aba (Safari, Google Chrome, Arc, Brave Browser ou Microsoft Edge). Sem
      navegador fixado, o Deck usa o que achar com a aba aberta e, sem aba, o navegador padrão do Mac. Leitura
      tolerante: valor desconhecido volta para `auto`. Um PUT de painel velho sem a chave não apaga a escolha.
    - Escolha nos Ajustes, em Este Mac, grupo WhatsApp: Automático, App ou WhatsApp Web. Ninguém digita URL.
    - Detecção `auto`: se o banco do app teve atividade nos últimos 30 minutos (ele ou o arquivo `-wal`), a
      origem é o app, que dá a lista por conversa e nem consulta o navegador. Banco parado ou ausente e
      uma aba de web.whatsapp.com aberta em algum navegador: origem web. Sem aba: banco parado, fica no app
      como sempre foi. Banco ausente (Mac sem o app), vai para web e abre web.whatsapp.com.
    - O total do web vem do título da aba, "(23) WhatsApp". O navegador não dá lista por conversa nem conteúdo
      de mensagem, e o Deck não finge que dá. O Estado ganha `whatsapp.origem`, `navegador` e `aberto`.
    - O Mac consulta cada navegador por AppleScript pelo Executor, só se o processo estiver aberto
      (`pgrep`) e só em abas cuja URL começa em https://web.whatsapp.com, com tempo limite de 4 s por navegador, e a decisão fica guardada por 2 s. Na primeira vez o
      macOS pede a Automação de cada navegador, e o aviso de permissão negada só aparece quando a origem é
      `web` fixa.
    - "Abrir no Mac", "Responder no Mac" e a tecla do WhatsApp, com a origem web, trazem a aba para a frente
      (e o navegador) ou abrem web.whatsapp.com. Origem app: abre o app, como antes.
20. "Mac desconectado" só quando o Mac sumiu de fato. Palavras dele: "sinto que a conexão está caindo com
    frequência, o celular apresenta o mac reconectando várias vezes. Não sei se é pq você está mexendo ou se
    é do app mesmo". O log do Mac mostrou 17 aberturas do Deck.app em 11 h (8 delas em 17 minutos de teste, a
    cada uma o iPhone ficou 7 a 14 s sem o Mac) e a tela fechando com 2 falhas, cerca de 2 s. Com o painel já
    aberto, a tela só fecha com 3 falhas seguidas e mais de 5 s sem resposta boa (o exemplo dele). Substitui os
    10 s do 14.11, que não foi feito, e o ponto amarelo do 14.11 continua de fora. O tempo limite de um pedido
    sobe de 3 s para 5 s (o estado leva até 2 s na primeira leitura depois que o Deck abre, mais o Bluetooth). No
    Mac, a fonte que já tem valor guardado e venceu (WhatsApp, agenda, sessões, uso, Spotify) é esperada por
    0,5 s: passou disso, o iPhone recebe o último valor bom e a leitura termina em segundo plano. O selo do Dock
    do WhatsApp entra nesse mesmo prazo. Na primeira abertura da página, sem painel ainda, uma falha já fecha a
    tela, como antes.
    Com o Mac pendurado (aceita a conexão e nunca responde, cada pedido espera os 5 s), 3 falhas deixavam a
    tela com cara de ao vivo por uns 16 s: então 2 falhas seguidas e mais de 10 s sem resposta boa também
    fecham (cerca de 11 s).

Ajustes de UX (11/11/2026, teste do Leonardo no iPhone):

20. Resposta otimista em todo o painel. Palavras dele: "Sinto que os comandos como do Spotify estão com muito delay, clico
    play/stop e a UI demora pra responder. A música para mas pro play virar stop demora uns segundos. Use opthimistic UI em
    todo app e painel." Spotify, teclas, perfis, blocos e o editor de tecla (Salvar e Excluir) mudam no toque e só voltam se
    o Mac recusar. Na recusa o editor reabre com o que a pessoa digitou (decisão minha, corrigida na verificação do PR:
    antes o editor esperava o Mac).
21. Relógio quando sobra espaço. Palavras dele: "Relógio desalinhado, é pq nao configuramos as IAs? Temos que mudar a
    disposição do relógio então pra preencher esse espaço. Deixar a data em cima e a hora e min um em cima do outro." A
    mesma regra vale onde há o mesmo buraco: B deitada sem sessões e em pé com blocos a menos (seção 3).
22. Relógio em tela cheia. Palavras dele: "Poder clicar no relógio e a tela ficar só com ele e a data bem grande tipo
    fliqo". Tocar no relógio abre, tocar sai (seção 5).
23. Player em tela cheia, com aleatório e repetir também no pequeno. Palavras dele: "queria clicar no spotify (capa da
    música) e abrir um player na tela inteira com mais informações, dando pra ver a próxima da lista (colocar função de
    repetir música ou álbum como tem no spotify em ambas as visualizações)". A próxima da fila e o repetir só a música
    ficam de fora: o AppleScript do Spotify não entrega (seção 5). Precisa de login na API do Spotify, que o Deck não tem.
    Emular o "repetir a música" pelo painel foi descartado: o painel só vê o Spotify enquanto está aberto.
24. Sessões em cartões. Palavras dele: "A visualização das sessoes esperando acho que está ruim de ler. às vezes tem
    muito texto da sessão e nao consigo ler tudo. Pensei em um esquema de clicar no card das sessoes esperando e cada
    sessão vira um card, clicando no card ela abre com a resposta que tenho fornecer". O "Responder" saiu e a sessão
    aberta mostra a pergunta inteira com Dispensar e Voltar (seção 5). Responder dali ficou de fora: o Mac não tem rota para
    entregar uma resposta a uma sessão do Claude (só lê as sessões esperando), e o link para abrir a sessão no app do Claude
    do iPhone não existe. Quem responde faz isso na própria sessão.

25. Spotify completo (11/11/2026). Palavras dele: "Quando disse de clicar na capa e abrir um player, tem que ter opção de
    tocar em X dispositivo, mexer no volume, etc." E a regra dele: "tudo deve ser configurável para outros usuários no
    painel. não apenas deixar pré configurado pro meu uso". Decidido:
    - Volume pelo AppleScript (volume do Spotify e volume do Mac), que funciona sem login. Aparelhos do Spotify Connect,
      curtir, fila e repetir só a música vêm da API do Spotify e pedem login.
    - Login por OAuth com PKCE e redirecionamento local para o próprio Deck, sem segredo. Cada pessoa cria o seu app grátis
      e cola o Client ID em Ajustes > Este Mac > Spotify. O Deck não leva chave embutida, para valer para qualquer usuário.
    - Endereço de retorno fixo `http://127.0.0.1:4778/retorno` (o Spotify não aceita `localhost`), aberto só durante o login.
      Se a 4778 estiver ocupada, o Deck avisa em vez de trocar de porta, porque a pessoa registrou o endereço exato no Spotify.
    - Tokens e chave no Chaveiro, fora do `config.json` (o painel lê o config). Sem login, o que funcionava pelo AppleScript
      segue igual e o resto some do painel (`conectado` falso no estado, 409 nas rotas).
    - Repetir só a música: `POST /api/spotify/repetir?modo=faixa|nao|contexto`, pela API (pede login). O `repetir?v=1|0` do AppleScript (item 23) segue como estava e só vê a lista. O estado ganha `repetirFaixa` ao lado do `repetir` de antes.
    - A próxima da fila (item 23) passa a vir de `GET /api/spotify/fila` quando o Spotify está conectado.
26. Apps do Mac e ações de app nas teclas (11/11/2026). Palavras dele: "Quando clico em nova tecla nao tem a lista de apps do
    mac/iphone pra eu abrir no deck. Quero abrir o email e selecionar qual conta quero abrir por exemplo, podendo ter 3 teclas
    com 3 emails diferentes. Nao consigo nessa versão" e "tudo deve ser configurável para outros usuários no painel. não apenas
    deixar pré configurado pro meu uso". Decidido:
    - O Mac entrega a lista de apps instalados (nome, id do pacote e ícone) e, por app, as ações que ele sabe fazer, com as
      escolhas lidas do próprio Mac de quem usa: as contas do Mail, as pastas das Notas, os navegadores. Nenhuma conta, e-mail ou
      endereço vem escrito no Deck (seção 9, "Apps do Mac e ações de tecla").
    - O contrato é um campo opcional `acao` na tecla do tipo `app`, não um tipo novo: a tecla segue sendo "abrir um app", só que
      numa coisa específica, e config antiga continua valendo sem mudança. Três teclas de e-mail são três teclas `app` com o Mail e
      cada uma com a sua conta.
    - Gmail e links abrem no navegador padrão ou no escolhido (o `valor` da tecla). O Gmail aceita o número da conta (`authuser`)
      ou o e-mail, sem o Deck guardar senha nem entrar em nada.
    - Apps do iPhone não entram: o iOS não deixa um app listar os outros, e a tecla roda sempre no Mac (invariante 12).
    - A lista de contas e pastas abre o Mail ou as Notas escondidos quando estão fechados, porque só o app sabe suas contas. O macOS
      pede a permissão de Automação na hora do uso, e a falta dela aparece como aviso no lugar da lista.
27. Renovação silenciosa e pelo Wi-Fi (11/11/2026). Palavras dele: "Como está a renovação automática? Como está funcionando
    ou como deveria funcionar? Alguma condição específica pra fazer essa renovação? quero que seja feito tudo internamente
    sem precisar abrir telas." Decidido:
    - Auditoria: a renovação só chama `xcrun`, `bash`, `xcodegen`, `xcodebuild` e `security`. Nunca `open`, `osascript`,
      Xcode ou Finder, e o Deck segue só na barra (`LSUIElement`). Um teste do núcleo trava essa lista.
    - Renova pelo Wi-Fi quando o iPhone está pareado com o Xcode pela rede: o `devicectl` lista o aparelho disponível sem
      cabo (`transportType` `localNetwork`). O caminho (cabo ou Wi-Fi) vai para o `deck.log`. A escolha do alvo passa a
      ser só iPhone (antes era o primeiro aparelho disponível, o que com a rede poderia ser um iPad ou um relógio).
    - Só avisa quando o prazo aperta (12 horas depois da hora de renovar), como já era. Renovar sozinho ou falhar com
      folga não mostra nada.
    - O motivo "O iPhone não está no cabo" virou "O iPhone não está ao alcance do Mac (nem no cabo, nem no mesmo
      Wi-Fi)", porque a antiga ficaria falsa com o Wi-Fi. É o único texto antigo que mudou (e o teste dele).
    - Ajustes > Conectar iPhone, no grupo do app nativo, ganha uma nota com as condições. Texto longo vive em
      `docs/renovacao.md`.
    - Sem interruptor para ligar ou desligar a renovação ou o Wi-Fi: o Deck segue o que o Xcode enxerga e a conta
      que a pessoa pôs nele, nada é fixo para o Leonardo. Se ele quiser o interruptor, é um item à parte.

27. Segunda leva do painel (11/11/2026). Palavras dele, sobre a agenda: "No calendário deve ser possível arrastar o dedo pra
    passar os meses. As setinhas são bem pequenas e fica ruim de clicar." E a regra dele: "tudo deve ser configurável para
    outros usuários no painel. não apenas deixar pré configurado pro meu uso". Decidido:
    - Agenda: o mês segue o dedo e as setas têm 44 pt. "Entrar na reunião" aparece no evento que tem link de Meet, Zoom ou
      Teams. Meet e Teams abrem no navegador padrão do Mac. O Zoom abre no app do Zoom se ele estiver instalado e no
      navegador se não (confirmado por ele). Quem usa outro navegador padrão ou não tem o Zoom é atendido sem configurar nada,
      porque vale o que o Mac de quem usa tem. O iPhone nunca manda o Mac abrir um endereço qualquer: só `https` desses três
      serviços passa, nos dois lados.
    - Editor de tecla: a lista de apps do Mac de quem usa, com busca (sem ligar para acento nem caixa) e o ícone de cada um,
      vem de `GET /api/apps`, e o que a tecla faz além de abrir vem de `GET /api/apps/<id>/acoes`. Para as 3 teclas do Mail,
      cada uma numa conta: escolhe o Mail, "Abrir a caixa de entrada de uma conta" e a conta, e o nome da tecla acompanha
      ("Mail Trabalho") enquanto a pessoa não mexe nele. Mac antigo, sem as rotas, cai na lista curta de antes. A tecla de app
      sem ícone na página mostra o que o Mac entrega. "Navegador padrão" aparece na lista porque o Mac o oferece (link e Gmail).
    - Player: o volume, os aparelhos, curtir, a fila e repetir só a música estão na seção 5, e some o que não está disponível
      (sem login só o volume).
    - Sessões: "Abrir no Mac" traz o terminal da sessão para a frente, descoberto pelo processo, ou abre o Terminal na pasta do
      projeto (seção 5). A escolha do app de terminal não é configurada porque vem do próprio Mac.
28. Acessos do Mac mostram o estado real de cada acesso. Palavras dele (11/11/2026): "As permissões não aparecem
    no painel, o app pede para calendários entre outros." A seção só listava o que tinha sido recusado, e a
    detecção nunca disparava: a Acessibilidade e o Acesso Total ao Disco dependiam de uma marca de "pedido"
    que nenhum código gravava, Calendários só contava recusa explícita (nunca "não perguntado"), a Automação
    só olhava o Spotify, e Bluetooth e Rede Local nem existiam. Sem recusa a seção sumia do menu lateral,
    então a pessoa nunca via nada e o macOS perguntava de surpresa. Decidido (tudo configurável por quem usa,
    nada fixo do Mac dele: a lista vem do que está instalado e da config `whatsapp`):
    - A seção fica sempre no menu lateral, com o selo vermelho só para o que foi recusado. O aviso amarelo do
      menu da barra continua só para recusa (invariante 12: nada de lista de pedidos de cara no menu).
    - Cada linha mostra Liberado, Não perguntado, Recusado ou Sem como conferir. Lido sem abrir janela do
      macOS: Calendários (acesso total, o "só escrever" do macOS 14 não vale), Bluetooth, Automação com o app
      aberto (o macOS só responde assim, então a última resposta fica guardada para quando ele fecha),
      Acessibilidade e Acesso Total ao Disco (o macOS não separa "nunca pedi" de "recusei": o Deck lembra que
      foi ele quem pediu, e só depois disso "não liberado" vira Recusado).
    - Rede Local: o macOS não deixa conferir sem perguntar. Vale Liberado quando um iPhone já falou com o Mac
      pelo Wi-Fi, ou a resposta guardada do último "Permitir". Fora isso a linha diz "Sem como conferir" e
      oferece "Permitir".
    - Automação dos navegadores: uma linha só, com o pior estado entre os navegadores que valem (o fixado em
      `whatsapp.navegador` ou, sem fixo, os instalados) e o detalhe de quais. Some quando o WhatsApp é lido só pelo app.
    - "Permitir" aparece onde o macOS ainda não perguntou e faz o Deck pedir na hora: a janelinha do macOS só
      aparece depois do toque, nunca ao abrir a seção.
    - Rede Local recusada guardada continua com o "Permitir": a pessoa pode ter liberado depois nos Ajustes do
      Sistema, e só pedir de novo (que o macOS responde sem janela) limpa a resposta velha. Sem isso a linha
      ficava "Recusado" para sempre.
    - O aviso amarelo do menu da barra segue contando só o que foi recusado. "Não perguntado" não é problema
      (o macOS pergunta na hora do uso e nada é obrigatório), e contar isso deixaria o aviso fixo para quem
      escolheu não liberar. O estado de cada acesso fica na seção dos Ajustes, sempre visível.

29. Client ID do Spotify embutido no Deck (11/11/2026). Palavras dele: "chave do spotify tem que ser criada toda vez pelo
    usuario? outros apps nao pedem pra fazer isso". Muda a decisão do item 25 ("o Deck não leva chave embutida"). Decidido:
    - O dono cria o app no developer.spotify.com uma vez e o Client ID vai no código (`ChaveSpotify.embutida`). Com PKCE o
      Client ID não é segredo, então pode ficar no repositório público (invariante 4 não é violada: não há segredo).
    - Quem usa só clica em "Conectar ao Spotify". O campo da chave vai para "Avançado: usar a minha própria chave do app",
      recolhido. Chave colada vence a embutida (quem já tinha colado a sua segue igual) e "Voltar" esquece a colada.
    - Sem chave embutida (fork que não configurou, ou valor que não tem 32 letras e números), a tela fica como era no item 25.
    - Limite: o app do Spotify em modo de desenvolvimento aceita até 25 contas (e cada conta precisa estar na lista de
      usuários do app no dashboard). Quem passar disso usa a própria chave, no Avançado. O texto da tela diz isso.
    - Conta fora da lista (11/11/2026). Palavras dele: "nao consigo ficar cadastrando gente aleatória". Quando o Spotify
      recusa a conta e a chave em uso é a **embutida**, o Deck não mostra o erro cru: diz "Os extras do Spotify (aparelhos,
      curtir, fila, repetir a música) pedem uma chave sua. Leva 2 minutos.", abre o "Avançado" na hora com o passo a passo e
      o endereço de retorno com "Copiar", e desconecta (nada de estado meio logado). Dois caminhos: o Spotify deixa logar e
      responde 403 na Web API ("User not registered in the Developer Dashboard", "the user may not be registered"), ou
      recusa já no login (o retorno traz um erro que não é o de Cancelar, e a troca do código pode trazer a mesma mensagem).
      Com chave própria o erro segue como antes. Tocar, pausar, pular, volume e capa seguem sem login.
    - O README explica como um fork configura a própria chave.
30. Acessibilidade "Recusado" com o interruptor ligado, e o login do Spotify que não termina (11/11/2026). Palavras dele:
    "nao consigo permitir a acessibilidade mesmo já liberado" e "nao tem como saber se conectou de fato".
    - Acessos do Mac: a assinatura ad hoc pura tem como requisito o cdhash de cada compilação, e o macOS amarra a permissão a
      esse requisito. Reinstalar por cima deixa o Deck ligado na lista, mas "outro app". O `build.sh` agora assina com o
      requisito estável `identifier "<id do app>"` (`scripts/assinar-deck.sh`, ou um certificado de verdade em
      `DECK_ASSINATURA`). A permissão dada a um build antigo (ad hoc) ainda precisa ser refeita uma vez.
    - Acessibilidade e Acesso Total ao Disco em "Recusado" explicam na própria linha: "tire o Deck da lista com o botão menos
      e adicione de novo". O botão "Abrir Ajustes do Sistema" já leva à página certa.
    - Spotify: o login sai do "Esperando" sempre (conectado, recusado, cancelado ou tempo esgotado, com texto que diz o que
      olhar). O Deck grava cada passo no deck.log, sem código nem token. Conectado mostra "Conectado como <nome>" e o botão
      Desconectar. A chave do Deck guardada no Chaveiro não conta como "própria": com a chave embutida o campo vem vazio e o
      Avançado recolhido.
    - Spotify, correção da verificação (11/11/2026): conectado não volta ao "Esperando" enquanto o nome da conta carrega, e a
      conta recusada só no /me (fora da lista) mostra o Avançado na hora. O texto de tempo esgotado não aponta mais o endereço
      de retorno como causa. A causa do travamento real segue sem confirmação: o próximo teste manual lê o deck.log.
30. iPhone desconectado pelo Mac volta a pedir pareamento (11/11/2026). Palavras dele: "Desconectei o iPhone e tá
    demorando muito pra conectar pelo Bluetooth ou cabo. Não tá conectando na real."
    - Causa: "Desconectar iPhone" no Mac muda o código de acesso. O app do iPhone só esquecia o Mac ao receber um 401 numa
      resposta, mas com o código velho nenhum canal conecta (o cabo derruba o Mac sem prova e o Bluetooth recusa), então
      nenhum pedido ia e nenhum 401 voltava. A tela ficava em "Mac desconectado" para sempre, e o aviso do Mac
      ("Ele volta a pedir pareamento") não acontecia.
    - Agora: se o Mac já conhecido pelo Bluetooth recusa o iPhone 2 vezes seguidas, o app esquece o pareamento e volta à tela
      de parear, igual ao 401. Duas vezes porque uma só poderia ser um instante da troca de código.
    - O Bluetooth do Mac passou a aceitar também o código anterior na folga de 10 min do rodízio (o cabo e o HTTPS já
      aceitavam), senão um iPhone que ainda não recebeu o código novo seria esquecido por engano.
    - Precisa atualizar o app do iPhone: a parte de esquecer o pareamento mora nele.
    - Correções da verificação (11/11/2026): o cabo sozinho também esquece. Se o Mac que conecta pelo cabo não prova o
      código 2 vezes seguidas, o app esquece o pareamento, mesmo com o Bluetooth desligado ou sem permissão (o pedido dele
      dizia "Bluetooth ou cabo"). E o iPhone pareado só pelo cabo, que ainda não guardou o id do Bluetooth, conta uma
      rodada em que todos os Macs por perto recusam: 2 rodadas seguidas e esquece. Quem conecta pelo cabo com prova
      certa zera a contagem.

30. Três ajustes de tela do Mac (11/11/2026). Palavras dele: "nao precisamos do "Repositório". podemos usar apenas o
    "Gostou do Deck?" em primeiro lugar. colocar um botao amarelo e ícone de estrela ao invés do azul", "pode remover
    isso" (o grupo Avançado > Configuração, com o "Mostrar no Finder" do config.json) e "temos que explicar que pelo
    wifi é o PWA e que ele é limitado em funcionalidades".
    - Sobre > Projeto aberto: sem a linha Repositório. "Gostou do Deck?" vem primeiro, com botão amarelo (token
      `Tema.Cor.estrela`, texto escuro nos dois temas) e a estrela `star.fill`. Licença e "Achou um erro?" ficam.
    - Este Mac: o grupo Avançado sai. O Avançado do Spotify (chave própria) é outro e continua.
    - Conectar iPhone > Parear pelo Wi-Fi: a nota diz que é o PWA da Tela de Início e o que ele tem a menos que o app
      nativo, só o que existe no código: sem cabo e Bluetooth (item 9), sem dados quando o iPhone sai do Wi-Fi e tela
      acesa só pelo Wake Lock do Safari, que pode falhar (no app nativo é a casca que segura a tela).

31. Tecla de comando roda no shell de login do usuário (12/11/2026). Palavras dele: "coloquei um comando na tecla (mudar
    tela/teclado, jogo, trabalho) e ele deu o aviso erro zsh:1 'mudar' comandos criados ele não entende. Libera pra ele
    entender. Esses aí eu dou no terminal e corre tudo bem."
    - Causa: o Deck rodava `/bin/zsh -c <linha>` sem login e sem interativo, então o .zshrc e o .zprofile não eram lidos e
      alias, função e PATH do usuário não existiam (`zsh:1: command not found: mudar`).
    - Agora: a tecla de comando roda no shell de login do usuário (getpwuid, não a variável SHELL, caindo em /bin/zsh) com
      `-l -i -c` em zsh, bash e fish (só `-l` em sh e outros), lendo o perfil como o Terminal. A linha segue como argumento
      do `-c`, nunca colada em string de outro shell. O limite de 10 s, o vigia e o stdin em /dev/null continuam (sem tty
      para travar), e a saída do perfil (banner) só aparece se o comando falhar, pela última linha como antes.
    - Comando que não existe de verdade (status 127) avisa "Comando não encontrado: <nome>". Só a tecla de comando muda:
      os comandos internos do Deck (osascript, open, shortcuts) seguem no zsh puro, de propósito.
32. Deck Bancada (12/11/2026). Pedido da frente deck-bancada: testar as telas do Mac sem tocar no Deck instalado (decisão da
    frente, sem citação dele). É o mesmo app do Mac com outro nome e identificador (`com.leonardorejani.deck.bancada`), ícone com a faixa laranja "BANCADA" e a barra de
    menus com a diagonal pintada. Fica em `~/Applications/Deck Bancada.app`, instalado por `scripts/bancada.sh`, que
    nunca abre o app. Decidido:
    - Dados próprios: config e certificados em `~/Library/Application Support/Deck Bancada/`, log em
      `~/Library/Logs/Deck Bancada/`, porta 4791 e serviços de Chaveiro com o prefixo `com.leonardorejani.deck.bancada.`.
      Nunca lê nem grava os itens do Deck real, então nunca pede a senha dele.
    - Primeira abertura: copia o `config.json` do Deck real (só leitura) com a porta trocada para 4791. Se a bancada já
      tem config, não mexe. Os certificados não vêm junto, a bancada cria os dela.
    - Sem iPhone e sem rede: nada de cabo, Bluetooth nem renovação do app do iPhone, e o servidor escuta só no
      loopback, então não aparece para outros aparelhos.
    - Código em `mac/Nucleo/Variante.swift`. Testes: `mac/Testes/VarianteTestes.swift` e `scripts/teste/bancada.test.sh`.

Nada em aberto que trave a fase 1. Falta só confirmar, na construção, o link que abre uma sessão
específica no app do Claude do iPhone (se não existir, cai no "mostra a pergunta").

Teste do Deck 1.0 (11/11/2026, frente contas-ia): "nao consigo configurar conta do claude" e "as que consigo
ficam sem medição". Decisão: o Deck mede o uso pelo token de `claude setup-token` lendo os cabeçalhos
`anthropic-ratelimit-unified-7d-*` de um pedido de 1 token ao Claude, porque o endereço `/api/oauth/usage` pede
o escopo `user:profile` e o token de setup-token só tem `user:inference` (403). Conta da troca de contas sem
medição do autoswitch passa a ser medida pelo token do perfil (type oauth_token). A leitura fica em cache de 5 min.

31. Sessões com o contexto do que esperam (12/11/2026). Palavras dele: "quando clico no card da sessão ele não mostra nada de
    contexto que eu tenho que aprovar, se for assim não muda nada eu abrir isso no celular." E: "muda o visual, deixa mais
    bonito aí sla, intuitivo e fácil de ler". Decisão: a sessão aberta mostra o pedido inteiro, o contexto e Abrir no Mac, e o
    cartão e a tela ganham hierarquia nova (seção 5). Sem responder pelo iPhone nesta versão. O Mac não vê o pedido de
    permissão (ferramenta e comando) porque o `state.json` não o guarda: o que existe é `needs` e a última mensagem da
    sessão no `timeline.jsonl`, e é isso que a tela mostra.
    Correção da verificação (12/11/2026): como o pedido é "sem segredo: mascare tokens", a máscara cobre também URL de banco
    com senha (qualquer esquema, não só http), par chave/valor em JSON com aspas e chave com underscore (`sk_live_...`). E
    "fácil de ler" inclui bloco de código com cerca (a cerca some e o comando fica como está), link, itálico, `__forte__` e
    citação sem a marcação.

## 14. Melhorias (10/11/2026)

Feitas no protótipo em 10/11/2026: 14.1 a 14.9 e 14.14, marcadas com **(feito)**. As outras
ficam para depois. Cada uma diz o problema, o que muda e como provar. As 11 primeiras saíram
da revisão do protótipo, e as 12 a 19 são ideias novas. Critério que guia todas: o mais fácil de
configurar e intuitivo possível.

### Deixar mais fácil

**14.1 Permissão só na hora do uso. (feito)**
- Problema: a seção de permissões e o passo da configuração inicial mostram quatro pedidos de cara,
  como tarefa. Os apps comuns não fazem isso.
- Muda: cada permissão é pedida pelo próprio macOS na primeira vez que o Deck precisa dela. Agenda
  e Spotify viram uma janelinha "Permitir" (um clique). Acessibilidade só aparece quando a pessoa
  cria a primeira tecla do tipo Teclado. A lista por conversa do WhatsApp pede acesso na primeira
  vez que a tecla do WhatsApp abre a lista, e até lá a tecla mostra só o total, que vem do ícone no
  Dock sem permissão. ~~"Acessos do Mac" mostra só o que foi recusado, com o caminho para liberar,
  e some do menu quando não há nada recusado.~~ Revisto em 11/2026 (13, item 28): a seção fica sempre no menu e mostra o estado de cada acesso. ~~O passo de permissões sai da configuração inicial.~~
  Revisto em 10/11/2026, a pedido: o passo voltou como "Libere os acessos", com o nome do macOS e o
  motivo de cada um, nada obrigatório. O que ficar sem liberar continua sendo pedido na hora do uso.
- Prova: perfil "Usuário novo" termina a configuração sem ver pedido nenhum. Criar uma tecla
  Teclado mostra o pedido de Acessibilidade. Recusar faz o item aparecer em "Acessos do Mac".

**14.2 "O que aparece" sai: o Deck detecta sozinho. (feito)**
- Problema: ligar e desligar fonte de dado é configuração que ninguém precisa fazer.
- Muda: o bloco aparece quando a fonte existe. Spotify instalado: player. WhatsApp instalado: não
  lidas. Calendário com eventos: agenda. Pasta `~/.claude/jobs` com sessão: sessões. Uso das IAs:
  quando há conta. Esconder um bloco é no modo organizar do iPhone: cada bloco ganha um "−" na quina, e os escondidos
  ficam na barra do organizar com "+" para voltar. O espaço não fica vazio: sem Sessões o player
  ocupa a coluna, sem Uso o relógio ocupa a coluna (data em cima, horas sobre minutos, desde 11/11/2026).
  Os calendários mostrados seguem os que estão ligados no app Calendário do Mac. A seção sai dos
  Ajustes e o passo "O que o iPhone mostra" sai da configuração inicial (fica só a composição).
- Prova: perfil novo sem Spotify mostra o iPhone sem player e com as sessões no lugar. Instalar
  (simulado) faz o player aparecer sem tocar em nada.

**14.3 "Layout" sai. (feito)**
- Problema: a seção tem só a troca A/B, que já está no menu da barra.
- Muda: a troca fica no menu da barra e na configuração inicial. Os desenhos de A e B vão para o
  menu, pequenos, no lugar dos dois botões de texto.
- Prova: o menu troca a composição e o iPhone muda na hora.

**14.4 "Este Mac" sem Porta. (feito)**
- Problema: porta é assunto técnico. Quem não sabe o que é fica com medo de mexer.
- Muda: a porta sai da tela. Se a 4777 estiver ocupada, o Deck escolhe outra sozinho e o QR já
  leva a certa. Continua editável no config.json para quem precisa.
- Prova: com a 4777 ocupada (simulado), o pareamento funciona e a seção não mostra porta.

**14.5 Menu da barra mais curto. (feito)**
- Problema: "Editar teclas..." e "Ajustes..." abrem a mesma janela.
- Muda: fica só "Ajustes..." (⌘,), que abre em "Suas teclas".
- Prova: o menu tem estado, composição, aviso (se houver), Ajustes e Sair.

Com 14.1 a 14.5, os Ajustes caem de 8 para 5 seções: Suas teclas, Uso das IAs, Conectar iPhone,
Este Mac e Sobre o Deck (mais "Acessos do Mac", que desde 11/2026 fica sempre na lista).

### Acabamento

**14.6 "Remover" das contas só ao passar o mouse. (feito)** Hoje são três botões vermelhos sempre à vista.
Passa a aparecer no canto do cartão ao passar o mouse, e também no menu do botão direito. Prova:
print do painel sem vermelho em repouso.

**14.7 Desfazer no próprio aviso. (feito)** Excluir tecla ou conta mostra o aviso com o botão "Desfazer"
por 5 segundos, igual ao iPhone. O ⌘Z continua valendo. Prova: excluir e desfazer pelo botão.

**14.8 Renovação relativa. (feito)** "Renova sex 14h" vira "renova em 3 dias" ("amanhã", "hoje às 14h" quando
perto). O dia exato fica no texto ao passar o mouse. Vale no Mac e no iPhone. Prova: contas com
renovação hoje, amanhã e em 5 dias.

**14.9 Contraste. (feito)** O "Feito por", os rótulos "Página N" e os textos em `--texto-3` sobem para
`--texto-2`, com contraste de pelo menos 4,5:1 no fundo `--tela-fundo`. Prova: medir o contraste no
teste.

### iPhone

**14.10 Tela antes de parear.** Quem abre o endereço sem estar pareado vê "Abra o Deck no Mac" com o
logo, os 3 passos e o campo do código curto. Hoje cai numa tela sem sentido. Prova: abrir a página
sem o código de acesso.

**14.11 Queda de Wi-Fi tranquila.** Ao perder o Mac, o iPhone tenta de novo por até 10 segundos
mostrando só um ponto amarelo discreto no canto. Só depois escurece com "Mac desconectado". Voltou
nesse meio tempo: nada aconteceu. Prova: derrubar o servidor por 5 s (nada escurece) e por 15 s
(escurece).

### Ideias novas

**14.12 Prévia do iPhone ao vivo nos Ajustes.** Em "Suas teclas", uma miniatura do iPhone deitado,
na composição escolhida, mostra o resultado enquanto edita. Clicar numa tecla da miniatura escolhe
essa tecla no editor.

**14.13 "Testar" em qualquer tecla.** Botão no topo do editor que executa a tecla no Mac na hora
(abre o app, aperta as teclas, roda o comando ou o atalho), sem pegar o iPhone. Mostra se deu certo
ou o erro.

**14.14 Perfis de teclas. (feito)** Conjuntos de teclas por momento, por exemplo Ensaio, Culto e Trabalho.
No iPhone, a troca mora na tecla "Menu", na parte "Perfil" da folha (antes era um botão ao lado da
data, trocado em 10/11/2026, item 12 da seção 13). No Mac, cada perfil é
uma aba em "Suas teclas", com o ponto verde no que está no iPhone, e o menu da barra troca rápido.
Config v3 guarda os perfis. A v2 é lida e vira um perfil "Principal". Nasce da necessidade de palco: as teclas do ensaio não são as do
escritório.

**14.15 Segurar para confirmar ação de risco.** Comando que apaga, desliga ou reinicia (`rm`,
`shutdown`, esvaziar Lixeira, sair de todos os apps) só executa segurando a tecla por 1 segundo, com
um anel enchendo. O Deck reconhece sozinho, sem configuração.

**14.16 Aviso quando a tecla falha.** Se a ação não deu certo (app não existe mais, atalho apagado,
comando com erro), a tecla pisca em vermelho e o aviso diz o motivo em uma linha, com "Corrigir no
Mac". Hoje toda tecla parece funcionar.

**14.17 Exportar e importar a configuração.** Em "Este Mac": "Exportar teclas" gera um arquivo e
"Importar" lê de volta. Serve de backup e para levar as teclas para outro Mac.

**14.18 Atalhos de teclado nos Ajustes.** ⌘1 a ⌘5 para as seções, ⌘N nova tecla, Delete exclui a
tecla escolhida, setas andam na grade, ⌘F foca a busca de apps.

**14.19 Volume do Mac no player.** Arrastar na vertical sobre o player (ou uma faixa fina ao lado)
muda o volume do Mac, com o número aparecendo enquanto arrasta. Útil no palco, sem tirar a mão do
iPhone.
