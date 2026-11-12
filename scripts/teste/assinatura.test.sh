#!/usr/bin/env bash
# Prova que o requisito de assinatura do Deck é o mesmo em builds diferentes. A causa do "Acessibilidade Recusado com o
# interruptor ligado" era a assinatura ad hoc pura, cujo requisito é o cdhash de cada compilação. Só roda no Mac (codesign).
set -uo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
command -v codesign >/dev/null || { echo "assinatura: sem codesign, pulado"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
falhas=0
confere() { if eval "$2"; then echo "ok   $1"; else echo "FALHOU $1"; falhas=$((falhas+1)); fi; }

# dois "builds" do mesmo app: binários diferentes, mesmo identificador
fazer() { # <pasta> <binario-de-origem>
  mkdir -p "$1/Deck.app/Contents/MacOS"
  cp "$2" "$1/Deck.app/Contents/MacOS/Deck"
  cat > "$1/Deck.app/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.exemplo.deck</string><key>CFBundleExecutable</key><string>Deck</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PL
}
requisito() { codesign -d -r- "$1" 2>&1 | grep "designated =>" || true; }
fazer "$tmp/a" /usr/bin/true; fazer "$tmp/b" /bin/echo; fazer "$tmp/c" /usr/bin/true; fazer "$tmp/d" /bin/echo

# o defeito: ad hoc puro dá requisito diferente a cada build (e é o cdhash)
codesign --force --sign - "$tmp/c/Deck.app" >/dev/null 2>&1; codesign --force --sign - "$tmp/d/Deck.app" >/dev/null 2>&1
confere "ad hoc puro: o requisito é o cdhash e muda entre builds" '[ "$(requisito "$tmp/c/Deck.app")" != "$(requisito "$tmp/d/Deck.app")" ] && requisito "$tmp/c/Deck.app" | grep -q cdhash'

# a correção: o script dá o mesmo requisito, sem cdhash
bash "$raiz/scripts/assinar-deck.sh" "$tmp/a/Deck.app" >/dev/null 2>&1; bash "$raiz/scripts/assinar-deck.sh" "$tmp/b/Deck.app" >/dev/null 2>&1
confere "build assinado pelo script: requisito igual entre builds" '[ "$(requisito "$tmp/a/Deck.app")" = "$(requisito "$tmp/b/Deck.app")" ]'
confere "o requisito não leva cdhash" '! requisito "$tmp/a/Deck.app" | grep -q cdhash'
confere "o requisito é o identificador do app" 'requisito "$tmp/a/Deck.app" | grep -q "identifier \"com.exemplo.deck\""'
confere "o build novo cumpre o requisito que o macOS guardou do build velho" 'codesign --verify -R="identifier \"com.exemplo.deck\"" "$tmp/b/Deck.app" 2>/dev/null'
confere "a assinatura continua íntegra" 'codesign --verify --deep --strict "$tmp/a/Deck.app" 2>/dev/null'

# o ajudante do WhatsApp por QR (Go) mora em Contents/Helpers: o selo do app tem que continuar íntegro com ele dentro,
# e o requisito do app segue sendo só o identificador (o do ajudante é o dele)
fazer "$tmp/e" /usr/bin/true; mkdir -p "$tmp/e/Deck.app/Contents/Helpers"; cp /bin/echo "$tmp/e/Deck.app/Contents/Helpers/deck-whatsapp"
bash "$raiz/scripts/assinar-deck.sh" "$tmp/e/Deck.app" >/dev/null 2>&1
confere "app com o ajudante dentro: a assinatura continua íntegra" 'codesign --verify --deep --strict "$tmp/e/Deck.app" 2>/dev/null'
confere "app com o ajudante dentro: o requisito do app segue sendo o identificador" 'requisito "$tmp/e/Deck.app" | grep -q "identifier \"com.exemplo.deck\""'
confere "o ajudante tem identificador próprio (não o do app)" '! codesign -d "$tmp/e/Deck.app/Contents/Helpers/deck-whatsapp" 2>&1 | grep -q "Identifier=com.exemplo.deck$"'

[ "$falhas" = 0 ] && echo "assinatura: ok" || { echo "assinatura: $falhas falhas"; exit 1; }
