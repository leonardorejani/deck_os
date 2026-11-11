#!/usr/bin/env bash
# Critério de "terminou" do Deck (SPEC.md, seção 12): sintaxe do JS, validadores, auditor da tatile,
# build e testes do núcleo Swift. O CI roda o mesmo, menos o auditor (ele mora em ~/.claude).
set -euo pipefail
cd "$(dirname "$0")/.."
for f in prototipo/*.js; do node --check "$f"; done
for f in painel/*.js painel/teste/*.mjs; do node --check "$f"; done
for v in scripts/validators/*.ts; do bun run "$v" >/dev/null; done
# nenhum script abre o Deck por "open" (o ícone da barra de menus prende ao terminal)
bash scripts/teste/abrir-deck.test.sh | tail -1
# o requisito de assinatura do Deck é o mesmo em builds diferentes (as permissões do macOS sobrevivem a um build novo)
bash scripts/teste/assinatura.test.sh | tail -1
# auditores da tatile (design system do autor): só rodam onde a skill está instalada
if [ -d ~/.claude/skills/tatile ]; then
  node ~/.claude/skills/tatile/auditor/auditar.mjs prototipo | tail -1
  node ~/.claude/skills/tatile/auditor/auditar.mjs painel | tail -1
  # auditor de PWA da tatile: sai 1 se houver erro (manifesto, service worker, ícones)
  node ~/.claude/skills/tatile/modulos/pwa/scripts/auditar.mjs painel --sem-cache | grep '^resumo'
fi
# testes de tela do painel contra o Mac de mentira (precisam do Chrome, por isso só rodam onde ele existe)
if [ -d "/Applications/Google Chrome.app" ]; then DECK_TESTE_PORTA="${DECK_TESTE_PORTA:-4981}" node painel/teste/rodar.mjs | tail -1; fi
swift test --package-path mac 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | tail -3
# App do Mac (SwiftUI): compila e roda os testes só onde o Xcode existe (o CI Linux não tem).
if command -v xcodebuild >/dev/null 2>&1 && command -v xcodegen >/dev/null 2>&1; then
  (cd mac/App && xcodegen generate --quiet \
    && xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Debug -derivedDataPath build test 2>&1 \
       | grep -E "^/.*error:|Executed [0-9]+ tests|\*\* (BUILD|TEST) " | tail -3)
fi
swift test --package-path ios/Pacote 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | tail -3
node --check ios/Web/ponte.js
node --check ios/Web/casca.js
node ios/scripts/testar-ponte.js
# o app do iPhone empacota o painel/ deste repo (sem os testes), nunca o de outra worktree
bash ios/scripts/empacotar-painel.sh >/dev/null && [ -f ios/Pagina/canal.js ] && [ ! -d ios/Pagina/teste ]
echo "verificar: ok"
