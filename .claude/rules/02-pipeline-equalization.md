# Pipeline Equalization — Deck

A pipeline change never touches just 1 layer — it touches the coherent set. Skipping a layer = silent bug.

## The N layers

```
C1  SPEC          SPEC.md, PLANO.md (fonte da verdade do produto)
C2  PROTOTIPO     prototipo/ (fonte da verdade do visual, dados.js = formato da config)
C3  NUCLEO        mac/Nucleo + mac/Testes (pacote Swift sem tela: config, rotas, fontes, ações)
C4  MAC           mac/App (SwiftUI: barra de menus, Ajustes, configuração inicial)
C5  PAINEL        painel/ (a página do iPhone, servida pelo Mac ou dentro do app nativo)
C6  IOS           ios/ (casca nativa: ponte, cabo, Bluetooth)
```

Mudou o formato da config: C1, C2 (`dados.js`), C3 (`Config.swift`) e quem lê (C4, C5) no mesmo PR.
Mudou uma rota ou mensagem do canal: C3 e C5, e C6 quando existir.

## Required sequences by change type

### Add a new entity
1. Types/schemas (C1)
2. Migration (C2)
3. Repository/storage (C3)
4. Service (C4)
5. API/handler (C5/C6)
6. UI (C7-C9)
7. E2E smoke test

### Change a critical flow
1. Map all touched layers BEFORE coding
2. Each layer has an isolated test
3. Smoke test the full flow

## Anti-pattern: partial merge

❌ "I only touched the API, forgot to update the UI" → contract breaks in production
❌ "I changed the type, forgot to migrate the DB" → hydration error

**Before opening a PR:** mental checklist "did I touch C1-CN where needed? did I verify coherence?".

## Where to catalog a large change

Every change that reaches **3+ layers** becomes `docs/reference-cases/YYYY-MM-DD-title.md` documenting touched layers and decisions.
