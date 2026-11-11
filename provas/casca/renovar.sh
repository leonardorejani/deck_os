#!/usr/bin/env bash
# Prova 0.4: renova o app de teste sem abrir o Xcode. Gera o perfil (conta grátis), compila e reinstala.
# Uso: bash provas/casca/renovar.sh [id-do-aparelho]   (id em: xcrun devicectl list devices)
set -euo pipefail
cd "$(dirname "$0")"
aparelho="${1:-$(xcrun devicectl list devices 2>/dev/null | grep available | grep -m1 -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')}"
[ -n "$aparelho" ] || { echo "nenhum iPhone conectado e disponível" >&2; exit 1; }

xcodegen generate --spec project.yml --quiet
xcodebuild -project DeckProva.xcodeproj -scheme DeckProva -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates clean build \
  | grep -E "error:|BUILD" | tail -3
xcrun devicectl device install app --device "$aparelho" build/Build/Products/Debug-iphoneos/DeckProva.app \
  | grep -E "App installed|error" | head -2
