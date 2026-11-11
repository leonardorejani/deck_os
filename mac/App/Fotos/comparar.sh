#!/usr/bin/env bash
# Fotografa as telas do app (SwiftUI) e do protótipo e monta a comparação lado a lado.
#   mac/App/Fotos/comparar.sh [tela ...]
# Sem telas, todas. Saída em .teste/mac-{swift,proto,comparacao}-<tela>.png (fora do git).
# Depois, abra as três fotos de cada tela e corrija o app até bater. Veja o topo de main.swift.
set -euo pipefail
cd "$(dirname "$0")/../../.."
RAIZ="$PWD"
SAIDA="$RAIZ/.teste"
mkdir -p "$SAIDA"

(cd mac/App && xcodegen generate --quiet \
  && xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Debug -derivedDataPath build build 2>&1 \
     | grep -E "error:|BUILD" || true)

mac/App/build/Build/Products/Debug/DeckFotos.app/Contents/MacOS/DeckFotos "$SAIDA" "$@"

# servidor do protótipo numa porta livre acima de 4900
PORTA=4900
while lsof -iTCP:"$PORTA" -sTCP:LISTEN >/dev/null 2>&1; do PORTA=$((PORTA + 1)); done
python3 -m http.server "$PORTA" --directory prototipo >/dev/null 2>&1 &
SERVIDOR=$!
trap 'kill $SERVIDOR 2>/dev/null || true' EXIT
sleep 1
node mac/App/Fotos/prototipo-fotos.mjs "$PORTA" "$SAIDA" "$@"
node mac/App/Fotos/comparar.mjs "$SAIDA" "$@"
