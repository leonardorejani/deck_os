#!/usr/bin/env bash
# Compila o Deck para o iPhone e instala no aparelho conectado (conta grátis da Apple, sem abrir o Xcode).
# Uso: bash ios/instalar.sh [id-do-aparelho] [--abrir]     (id em: xcrun devicectl list devices)
set -euo pipefail
cd "$(dirname "$0")"
abrir=0; aparelho=""
for a in "$@"; do if [ "$a" = "--abrir" ]; then abrir=1; else aparelho="$a"; fi; done
aparelho="${aparelho:-$(xcrun devicectl list devices 2>/dev/null | grep -E "available|connected" | grep -m1 -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')}"
[ -n "$aparelho" ] || { echo "nenhum iPhone conectado e disponível" >&2; exit 1; }

bash scripts/empacotar-painel.sh
xcodegen generate --spec project.yml --quiet
xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build \
  | grep -E "error:|BUILD" | tail -3
xcrun devicectl device install app --device "$aparelho" build/Build/Products/Debug-iphoneos/Deck.app \
  | grep -E "App installed|error" | head -2
if [ "$abrir" = 1 ]; then
  xcrun devicectl device process launch --device "$aparelho" --terminate-existing com.leonardorejani.deck.iphone | grep -E "Launched|error" | head -2
fi
