# Plano de implementação do Deck

Criado em 10/11/2026, depois da aprovação do protótipo (PR #3), com as decisões dele do mesmo dia. Fonte da verdade do produto:
`SPEC.md`. Fonte da verdade do visual: `prototipo/index.html` (iPhone) e `prototipo/mac.html` (Mac).
Este arquivo diz só a ordem e a prova de cada fase.

**Entregável:** o Deck instalado no Mac (barra de menus) e no iPhone de duas formas, com o mesmo
painel nas duas:

1. **PWA**, para usar rápido: abre o endereço do Mac no Safari e adiciona à Tela de Início. Fala
   com o Mac pelo Wi-Fi de casa.
2. **App nativo**, para quem quiser instalar de fato: compilado e instalado pelo Xcode com conta
   grátis da Apple. Fala com o Mac pelo cabo e por Bluetooth, sem depender de Wi-Fi.

Nada roda na internet e nada passa por loja.

## 1. Como as duas formas dividem o mesmo código

O painel é uma página só (`painel/`). No PWA ela é servida pelo Mac. No app nativo ela vai dentro
de uma casca fina em Swift. A página nunca fala direto com a rede: ela fala com um "canal", e o
canal muda conforme a forma.

```
PWA no iPhone         --Wi-Fi, HTTPS---------->  Deck.app no Mac (barra de menus)
App nativo no iPhone  --cabo (USB) ou Bluetooth->  um núcleo de rotas só,
  a mesma página nas duas                          com uma porta de entrada por canal
```

As mesmas mensagens (estado, botão, configuração) valem em qualquer canal. Por isso o núcleo
(fase 1) e a página (fase 3) já nascem sem saber qual é o canal.

## 2. Decisões do Leonardo (10/11/2026)

| # | Decisão | Resposta |
|---|---|---|
| D1 | App do iPhone | As duas formas: PWA para usar rápido e app nativo opcional pelo Xcode, que ganha cabo e Bluetooth |
| D2 | Loja e conta paga | Nenhuma. "Não vou pagar pela loja só pra usar de forma pessoal" |
| D3 | Cabo e Bluetooth | Só no app nativo. O Safari do iPhone não alcança USB nem Bluetooth, então o PWA fica no Wi-Fi |
| D4 | Nome | Deck |

O que cada forma custa, para ficar claro:

- **PWA:** os dois aparelhos no mesmo Wi-Fi. Na primeira vez, o iPhone instala o certificado do
  Mac (um minuto, uma vez só). Sem ele a tela não fica acesa sozinha.
- **App nativo:** precisa de um Mac com Xcode e de uma conta grátis da Apple. A Apple faz o app
  vencer a cada 7 dias. Para ele ficar instalado de fato, o Deck do Mac renova sozinho a cada 5
  dias, em segundo plano, com o iPhone no cabo. Os dados do app não se perdem.

Conferido neste Mac em 10/11/2026: Xcode 26.6 instalado, o iPhone 15 Pro Max dele pareado com o
Xcode e uma identidade de assinatura "Apple Development" válida.

## 3. Fases

Ordem: 0, 1, depois 2 e 3 em paralelo, 4, 5, 6, 7, 8. Primeiro marco usável: fim da fase 3, o
painel aberto no Safari do iPhone falando com o Mac. Segundo marco: fim da fase 4, o PWA completo.
As fases 5 a 7 são o app nativo.

### Fase 0: preparar

| Item | Entrega | Prova |
|---|---|---|
| 0.1 | keepwright pronto para Swift: camadas `nucleo`, `mac`, `painel` e `ios` no `keepwright.config.json`, `verificar.sh` com build e testes do Swift, arquivos críticos atualizados | `verificar.sh` verde e CI verde |
| 0.2 | Prova técnica do ponto mais arriscado: um servidor de teste no Mac com HTTPS e certificado próprio, o iPhone dele instala o certificado, adiciona à Tela de Início, abre em tela cheia e a tela fica acesa | feito no iPhone dele, com o passo a passo anotado. Virou o teste final da fase 4 (`docs/provas/fase-4-pwa.md`) |
| 0.3 | Prova técnica da casca: um app de teste instalado no iPhone dele pelo Xcode com a conta grátis, com a página do protótipo dentro | o app aberto no iPhone dele. Se não instalar, as fases 5 a 7 saem e fica só o PWA |
| 0.4 | Prova técnica da renovação: reinstalar o app de teste pela linha de comando, sem abrir o Xcode e sem pedir nada na tela | rodar duas vezes seguidas sem toque humano. Se pedir algo, a renovação vira um comando de um passo com aviso no Mac |
| 0.5 | Spec: registrar as decisões desta página na seção 13 | PR aprovado |

As provas 0.2 a 0.4 são código descartável em `provas/`, com o resultado em `docs/provas/`. Se a
0.2 falhar em algum ponto (certificado, tela acesa), o plano é revisto com ele antes de seguir.

Limite conhecido do CI: o runner do CI é Linux e não compila app de Mac nem de iPhone. Por isso o núcleo fica
num pacote Swift sem dependência de tela, testado no CI. O build do app roda no Mac dele, pelo
`verificar.sh` no pre-push.

### Fase 1: núcleo do Mac (sem tela)

Pacote Swift `Nucleo`, em cima do que já existe em `mac/Nucleo`.

- Config: `config.json` com versão, perfis, perfil ativo, teclas, composição, contas, blocos e nome
  do Mac, no formato que o protótipo já usa em `dados.js`.
- Servidor HTTPS local com certificado próprio, código de pareamento curto e o código longo da API.
- Rotas: estado, botão, configuração e os arquivos da página, independentes do canal. O HTTPS é
  só a primeira porta de entrada.
- Fontes (spec, seção 7): agenda, Spotify com as cores da capa, WhatsApp só leitura, uso do Claude
  e do Codex, sessões esperando, tecla acesa.
- Ações: app, teclado, comando e atalho.

Prova: teste de cada fonte com dado de exemplo, teste de cada rota, e `curl` em cada rota no Mac
dele. Sem o código, nada responde. Fonte que falha devolve aviso, nunca derruba o estado inteiro.

### Fase 2: app do Mac (as telas do `mac.html`)

SwiftUI, como a spec manda (seção 9a, "Como é feito"). Os tokens da tatile viram um arquivo Swift
só, para não ter cor nem medida solta.

1. Ícone, barra de menus e o menu (perfil, composição, acessos recusados).
2. Ajustes: Suas teclas (perfis, páginas em abas, arrastar, editor em 2 passos com busca de app).
3. Ajustes: Uso das IAs e a janela "Adicionar conta" (token no Chaveiro).
4. Ajustes: Conectar iPhone (QR, código, endereço), Acessos do Mac, Este Mac, Sobre.
5. Configuração inicial em 7 passos.
6. Abrir junto com o Mac.

Prova: para cada tela, print do app ao lado do print do protótipo, conferido antes de entregar. A
configuração inicial feita do zero numa conta nova do macOS.

### Fase 3: página do painel (as telas do `index.html`)

`prototipo/index.html` vira `painel/`, a página de produção servida pelo Mac. Sai o dado de
mentira, entra o canal (nesta fase, o canal HTTPS).

1. As duas composições, deitado e em pé, com todos os estados da seção 6 da spec.
2. Modo organizar, editor, esconder e mostrar blocos, perfis.
3. Painéis: WhatsApp, Agenda, Sessões.

Prova: no Chrome em 932 x 430 e 430 x 932, falando com o Mac de verdade. Auditor da tatile com 0
erros. Os testes de hoje em `.teste/` viram testes do repo.

### Fase 4: PWA no iPhone

Manifesto e ícone, tela cheia, service worker (abre na hora mesmo com o Mac desligado e mostra
"Mac desconectado"), tela sempre acesa, deslocamento contra queima de tela (spec, seção 11) e o
pareamento pelo QR com a instalação do certificado.

Prova: auditor de PWA da tatile, e o teste no iPhone dele: parear pelo QR, instalar na Tela de
Início, abrir em tela cheia, executar uma tecla no Mac, desligar o Mac e ver o aviso.

Feito em 11/11/2026 (`docs/provas/fase-4-pwa.md`): manifesto e ícones, service worker (só a casca, a API nunca entra em
cache), Wake Lock, deslocamento contra queima de tela e o pareamento pelo QR com o passo a passo do certificado. Provado no
Chrome headless e com o servidor real do Deck. A prova no iPhone dele (inclusive a antiga 0.2) é o teste final, com o passo a
passo no mesmo arquivo.

### Fase 5: app nativo do iPhone (a casca)

Projeto Xcode com a página `painel/` empacotada, a ponte entre a página e o Swift, tela sempre
acesa, deitado e em pé e vibração no toque. Antes do código de tela, protótipo do que é novo: como
o app nativo pareia sem QR de endereço e como o painel mostra o canal em uso. Ele aprova antes.

Prova: app instalado no iPhone dele pelo Xcode, abrindo o painel com o estado "sem Mac".

Protótipo aprovado em 10/11/2026 (`prototipo/nativo.html`): o pareamento principal é por Bluetooth com o
mesmo código nas duas telas, e a segunda via é o cabo com código digitado no iPhone. O aviso de canal
dura 3 segundos ao trocar. A renovação da instalação é automática.

### Fase 6: cabo

Começa por uma prova técnica: o Mac abre conexão com o app do iPhone pelo USB, sem rede. Depois o
canal dos dois lados, o pareamento pela segunda via (cabo e código digitado no iPhone) e a reconexão ao plugar de novo.

Feito em 10/11/2026 (`docs/provas/fase-6-cabo.md`), faltando só a prova com o Wi-Fi do iPhone desligado.

Prova: iPhone em modo avião e Wi-Fi do Mac desligado. O painel mostra o estado ao vivo e uma tecla
executa no Mac. Tirar e pôr o cabo volta sozinho.

### Fase 7: Bluetooth

Começa por uma prova técnica com a vazão medida, que define o tamanho da capa e dos ícones nesse
canal. Depois o canal, o estado enxuto e a troca automática: cabo quando está plugado, Bluetooth
quando não. O caminho principal de pareamento (o iPhone lista os Macs e os dois mostram o mesmo
código) entra aqui, porque depende do canal Bluetooth.

Prova: sem cabo e sem Wi-Fi, o painel atualiza e a tecla executa. Puxar o cabo no meio do uso não
derruba a tela.

Feito em 10/11/2026 (`docs/provas/fase-7-bluetooth.md`): vazão medida (uns 25 KB/s), canal cifrado, pareamento principal,
troca automática. Faltando só a prova de ponta a ponta no iPhone com o Bluetooth do aparelho ligado.

Ligado no `Deck.app` do Mac em 10/11/2026: o app abre o cabo e o Bluetooth junto com o HTTPS, o pedido de pareamento
(mesmo código, Recusar e Permitir) aparece no menu e em Conectar iPhone, e o grupo do app nativo mostra o canal em uso e o
prazo da renovação. O botão "Renovar agora" chama `ModeloApp.renovador`, que a fase 8 preenche.

### Fase 8: instalar e fechar

- `build.sh` e o `.dmg` do Mac, sem assinatura da Apple. Na primeira abertura é preciso liberar em
  Ajustes do Sistema > Privacidade e Segurança > "Abrir mesmo assim", uma vez só.
- `instalar-iphone.sh` para a primeira instalação do app nativo. Renovação automática pelo Deck
  do Mac a cada 5 dias (ou o comando de um passo, conforme a prova 0.4), com aviso se falhar.
- README no padrão dele, com os dois caminhos do iPhone: o rápido (PWA) e o completo (Xcode).
- Repo: open source, licença MIT (decisão de 11/11/2026, spec 13.11).
- Spec: seções 8, 9 e 10 ganham o app nativo como segunda forma.
- Teste de ponta a ponta do zero, nas duas formas.

Prova: o teste acima feito por ele, com o `.dmg` final, o PWA e o app nativo.

Feito em 10/11/2026 (`docs/provas/fase-8-instalar-e-renovar.md`): `build.sh` e o `.dmg`, `instalar-iphone.sh` e a renovação
automática no `Deck.app` (agenda de 5 dias, motivo em português, tentativa nova quando o iPhone volta ao cabo ou é
desbloqueado). Renovação provada de verdade pelo próprio app, com o vencimento do perfil andando 7 dias. Faltando: o README,
o teste de ponta a ponta do zero pelo Leonardo e esperar a primeira renovação por agenda (dia 5).

### Depois da primeira entrega

- Melhorias 14.10 a 14.13 e 14.15 a 14.19 da spec.
- Wi-Fi como terceiro canal do app nativo.
- Conta e compra.

## 4. Como cada fase é executada (keepwright)

- Um item da fase vira um PR pequeno, em rascunho, saído da `main`. Nunca commit direto na `main`.
- Todo PR traz teste que falha antes e passa depois, `verificar.sh` verde e CI verde.
- Merge só pelo `scripts/gh-pr-merge-safe.sh`, com o estado `CLEAN`, feito pela própria sessão
  depois da verificação adversarial. Ninguém espera o ok dele (decisão de 10/11/2026).
- Commit no padrão do repo: Conventional Commits em português, sem autoria de IA.
- Mudou o que a spec diz, muda a spec no mesmo PR. Protótipo e spec nunca ficam para trás.
- Erro achado no caminho vira teste e, se ensinar algo, lição em `docs/lessons/`.
- Quem faz: Opus planeja a fase e divide em PRs. Sonnet implementa e tenta quebrar. Haiku faz busca
  e a parte mecânica. Lotes de 4 agentes.
- Tela nova só nasce de protótipo aprovado. Se faltar tela no protótipo, para e protótipa antes.

## 5. Riscos

| Risco | O que acontece | Saída |
|---|---|---|
| Certificado local no iPhone (0.2) | sem ele a tela não fica acesa e o PWA não abre sem o Mac | provar no começo. Se falhar, avisar para desligar o bloqueio automático e rever com ele |
| SwiftUI não chegar no visual do protótipo | tela do Mac diferente do aprovado | comparar print por tela na fase 2. Se não fechar, levar a ele a opção de usar a página do protótipo dentro da janela |
| Firewall ou rede que isola aparelhos | o iPhone não acha o Mac | mensagem clara no pareamento e o endereço digitável como segunda via |
| O cabo ou o Bluetooth não funcionarem como esperado | o app nativo fica sem um dos canais | cada um começa por uma prova técnica. Se falhar, revisão com ele. O PWA não depende disso |
| Conta grátis da Apple | app nativo vence a cada 7 dias | o Mac renova sozinho a cada 5 dias (prova 0.4). Se não der, comando de um passo e aviso |
| WhatsApp mudar o banco local | lista por conversa para de vir | já previsto na spec: falha com aviso, a tecla mostra só o total |
