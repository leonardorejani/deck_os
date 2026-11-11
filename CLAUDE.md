# Deck

Painel de mesa no iPhone deitado (estilo StandBy) que controla o Mac: relógio, Spotify, agenda,
não lidas do WhatsApp, uso das IAs, sessões do Claude Code e teclas que executam coisas no Mac.
Fonte da verdade do produto: `SPEC.md`. Estado: construído (núcleo e app do Mac, painel PWA, app nativo do iPhone com cabo e
Bluetooth, build, instalação e renovação). Falta o teste de ponta a ponta no iPhone, que só o Leonardo faz (`docs/provas/teste-final.md`).

## How to read this project

| When | Go to |
|---|---|
| First time here | `SPEC.md` (o que é, telas, decisões e plano) |
| Implementar o app | `PLANO.md` (fases, ordem e a prova de cada uma) |
| Inviolable rules | `.claude/rules/01-invariants.md` |
| How to change things without breaking them | `.claude/rules/02-pipeline-equalization.md` |
| Disagreeing with the code? | `.claude/rules/03-epistemic-hierarchy.md` |
| Opening a PR | `.claude/rules/04-pr-flow.md` + `.github/PULL_REQUEST_TEMPLATE.md` |
| Going to merge a PR? | `.claude/rules/07-safe-merge.md` |
| Changed code? Prove it runs | `.claude/rules/08-empirical-proof.md` |
| Learned something? | `.claude/rules/05-lesson-cataloging.md` |
| Large investigation | `.claude/rules/06-parallel-workstreams.md` |
| Triaging an issue? | `.claude/rules/09-issue-triage.md` |
| Chronological history | `git log` |

> This table is the **equalization of CLAUDE.md**: every rule in `.claude/rules/`
> has a pointer here. A rule without a pointer = invisible to anyone reading only CLAUDE.md.
> The `validate-claude-md-sync` validator breaks CI if anything desyncs.

## Architecture

- `prototipo/`: protótipo navegável em HTML/CSS/JS puro, com os tokens do design system tatile
  (`prototipo/tatile/`). `index.html` é a tela do iPhone, `mac.html` o app do Mac, `dados.js` os
  dados e o formato da config que os dois compartilham (sincronizam entre abas do navegador). `nativo.html` (com `nativo.js`, `nativo.css` e `nativo-dados.js`) é a fase 5: pareamento do app
  nativo e canal em uso, em cima do painel de `index.html`, e segue o mesmo seletor que o `mac.html`.
- `painel/`: a página do iPhone de verdade (HTML/CSS/JS puro, mesmo visual do protótipo, dados do Mac pelo canal em `canal.js`, com o
  rodízio do código). O `Deck.app` leva ela empacotada e o `ios/scripts/empacotar-painel.sh` também. Testes de tela em `painel/teste`
  (`node painel/teste/rodar.mjs`, Chrome e o Mac de mentira em `servidor-falso.mjs`). Auditor: `node ~/.claude/skills/tatile/auditor/auditar.mjs painel`.
- `mac/`: app de barra de menus do Mac em Swift. `mac/Package.swift` é o pacote `Nucleo` sem tela
  (`mac/Nucleo`, testes em `mac/Testes`), que compila no Mac e no Linux do CI. Camadas do keepwright:
  spec, prototipo, nucleo, mac, painel (página do iPhone) e ios (app nativo, fases 5 a 7).
- `ios/`: app nativo do iPhone (fase 5). `ios/Pacote` é o pacote `DeckCasca` sem tela (protocolo `Canal`, ponte
  com a página, fluxo de pareamento, `X-Deck-Codigo-Novo`), testado no Mac e no Linux. `ios/App` é o SwiftUI e a
  WKWebView, `ios/Web` a ponte (`window.DeckCanal`) e as telas de pareamento, `ios/project.yml` o xcodegen.
  `bash ios/instalar.sh --abrir` empacota o painel, compila e instala no iPhone conectado.
  Fase 6, cabo: `Cabo.swift`, `Quadros.swift` e `Soquete.swift` existem nos dois pacotes (espelhos, com quadro de
  ouro igual nos testes). No Mac, `PortaDoCabo` abre a conexão pelo usbmuxd (`Usbmux.swift`) e o `DeckServidor` a liga. O `Deck.app` (`mac/App`) liga as duas portas sozinho (`ModeloApp.ligarNativo`), mostra o pedido de
  pareamento por Bluetooth e o app nativo em Conectar iPhone, e grava o log em `~/Library/Logs/Deck/deck.log`.
  Prova no iPhone: `docs/provas/fase-6-cabo.md`.
  Fase 7, Bluetooth: `Enlace.swift` (fio de bytes e os 6 dígitos), `EnlaceSeguro.swift` (aperto de mão cifrado, só onde há
  CryptoKit) e `VazaoBluetooth.swift` existem nos dois pacotes (espelhos). No Mac, `PortaDoBluetooth.ligar` anuncia o serviço
  e atende cada iPhone. No iPhone, `GerenteBluetooth` pareia e reconecta, e a `Casca` escolhe cabo ou Bluetooth.
  Prova no iPhone: `docs/provas/fase-7-bluetooth.md`.
  Fase 8, instalar e renovar: `./build.sh` gera `dist/Deck-1.0.dmg`, `./instalar-iphone.sh` faz a primeira instalação no iPhone e o
  `Deck.app` renova o app a cada 5 dias (`mac/Nucleo/Renovacao.swift`, `mac/App/Modelo/ModeloRenovacao.swift`).
  Prova no iPhone: `docs/provas/fase-8-instalar-e-renovar.md`.
- `painel/`: a página do iPhone. Fase 4, PWA: `manifest.webmanifest` e `icones/pwa/`, `sw.js` (só a casca em cache, a API nunca), `pwa.js`
  (registro do service worker, Wake Lock e deslocamento contra queima de tela) e `pareamento.js` (certificado pelo QR e código de 6
  dígitos). Quem carrega arquivo novo no `index.html` tem que pô-lo na lista `ESSENCIAIS` do `sw.js` (o `pwa.teste.mjs` cobra).
  Auditor: `node ~/.claude/skills/tatile/modulos/pwa/scripts/auditar.mjs painel` (0 erros). Prova no iPhone: `docs/provas/fase-4-pwa.md`.
- Regra do produto: **o Mac configura, o iPhone mostra** (ver `.claude/rules/01-invariants.md`).

### Como rodar e verificar

- Protótipo: `cd prototipo && python3 -m http.server 4871`, depois http://localhost:4871/ (iPhone) e
  http://localhost:4871/mac.html (Mac). Sem conta.
- Núcleo: `swift test --package-path mac`. No CI roda na imagem `swift:6.2` (Docker, no runner Linux).
- Pronto é `.claude/verificar.sh` verde (sintaxe do JS, validadores, auditor da tatile e testes do
  núcleo) e o print da tela conferido. Testes de navegador (Playwright) moram em `.teste/`, fora do git.
- Todo valor visual vem de token do tatile ou do bloco de tokens no topo de `deck.css`/`mac.css`.
  Auditor: `node ~/.claude/skills/tatile/auditor/auditar.mjs prototipo` (0 erros).

Every change consults `.claude/rules/02-pipeline-equalization.md` to know
which layers to touch and in what order.

## Stack

Swift (núcleo e app do Mac em SwiftUI) + página estática (protótipo e painel)

## Deploy

Sem deploy por enquanto. O iPhone recebe a página do próprio Mac (rede local) e o app do Mac sai como
`.dmg` fora da App Store (ver `SPEC.md`, seções 8 e 10). CI roda no runner próprio (rótulo `leve`) e, em PR de fora, no do GitHub.

Details and triggers in `.github/workflows/` + `docs/deploys/`.

## Safe merge (invariant)

Never `gh pr merge` directly. Always `bash scripts/gh-pr-merge-safe.sh <PR>`
(`mergeStateStatus CLEAN` gate). Automatic auto-merge only for inert Tier S
(`docs/`, `build-log.md`, `.planning/workstreams/`). Anything that touches
code, CI, rules, deploy, or config is Tier H: the AI merges it by itself once it is CLEAN,
`verificar.sh` is green and the adversarial check is closed (decision of 10/11/2026). Details in `.claude/rules/07-safe-merge.md`.

## Agents (isolated parallelism)

This project is git, so `.claude/agents/worker.md` uses
`isolation: worktree`: each spawned worker works in its own git worktree,
without colliding in the orchestrator's working tree or that of other parallel
workers. Use it for implementation fan-out. The worker delivers a ready branch,
and the merge follows `.claude/rules/07-safe-merge.md`. Read-only agents don't
use a worktree.

## Epistemic hierarchy (summary)

P1 reported symptom > P2 production logs > P3 database state > P4 code
> P5 abstract inference. When two sources contradict, the highest one wins.
Details in `.claude/rules/03-epistemic-hierarchy.md`.

## Pre-merge empirical proof (summary)

A change that alters runtime behavior only merges with **proof that it
works** against a real environment, pasted into the PR (`## EMPIRICAL VALIDATION`).
"The code is correct" / "type-check green" is NOT proof — compiling ≠ working.
3rd leg of the empirical tripod (analysis → hierarchy → proof). Gate
`validate-empirical-proof.ts`. Details in
`.claude/rules/08-empirical-proof.md`.

## Core principle

Every change catalogs a lesson immediately after merge. It does not pile up as "I'll
catalog it later". More than 1 day goes by, it's lost. See
`.claude/rules/05-lesson-cataloging.md`.

## Current date

> 2026-11-11
