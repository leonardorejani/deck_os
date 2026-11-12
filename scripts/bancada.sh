#!/usr/bin/env bash
# Compila o Deck Bancada a partir desta pasta (a worktree em que você está) e instala em ~/Applications/Deck Bancada.app,
# SEM abrir. A bancada é o app do Mac para testar telas sem tocar no Deck instalado: bundle, pasta de dados, porta (4791),
# log e Chaveiro próprios, sem cabo, Bluetooth nem renovação do iPhone (mac/Nucleo/Variante.swift).
# Abra depois pelo Finder: scripts/abrir-deck.sh "$HOME/Applications/Deck Bancada.app"
# Uso: scripts/bancada.sh
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
for f in xcodebuild xcodegen ditto; do
  command -v "$f" >/dev/null || { echo "Falta o $f. Instale o Xcode e rode: brew install xcodegen" >&2; exit 1; }
done
destino="$HOME/Applications/Deck Bancada.app"

echo "Compilando o Deck Bancada de $raiz..."
cd "$raiz/mac/App"
xcodegen generate --quiet
xcodebuild -project Deck.xcodeproj -scheme DeckBancada -configuration Release -derivedDataPath build-bancada \
  CODE_SIGN_IDENTITY="-" build | grep -E "error:|\*\* BUILD" | tail -5
app="$raiz/mac/App/build-bancada/Build/Products/Release/Deck Bancada.app"
[ -d "$app" ] || { echo "A compilação não gerou o Deck Bancada.app" >&2; exit 1; }
# Ajudante do WhatsApp por QR (Go) dentro da bancada, para a opção de QR funcionar nela. Sem Go, a bancada segue sem ele.
if bash "$raiz/helpers/whatsapp/build.sh" "$app/Contents/Helpers"; then :; else
  [ "$?" = 3 ] || { echo "O ajudante do WhatsApp não compilou" >&2; exit 1; }
fi
# Requisito estável: a bancada não perde as permissões do macOS a cada build novo.
bash "$raiz/scripts/assinar-deck.sh" "$app"

# Se a bancada estiver aberta, o instalador não mexe nela: o coordenador fecha e abre quando for testar.
if pgrep -f "$destino/Contents/MacOS/" >/dev/null 2>&1; then
  echo "O Deck Bancada está aberto. Feche e rode de novo para instalar a versão nova." >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
rm -rf "$destino"
ditto "$app" "$destino"
echo "Instalado: $destino (não foi aberto)"
echo "Para abrir: bash \"$raiz/scripts/abrir-deck.sh\" \"$destino\""
