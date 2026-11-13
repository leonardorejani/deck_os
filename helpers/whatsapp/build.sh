#!/usr/bin/env bash
# Compila o ajudante do WhatsApp por QR (Go, whatsmeow) em um binário universal (arm64 + x86_64), sem cgo.
# Uso: helpers/whatsapp/build.sh [pasta-de-saída]   (padrão: helpers/whatsapp/build)
# Sai com 3 se não há Go instalado: quem chama decide se o app segue sem a opção de QR.
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
saida="${1:-$aqui/build}"
command -v go >/dev/null || { echo "Falta o Go (brew install go): o Deck seguirá sem o WhatsApp por QR." >&2; exit 3; }
mkdir -p "$saida"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$aqui"
for arq in arm64 amd64; do
  CGO_ENABLED=0 GOOS=darwin GOARCH="$arq" go build -trimpath -ldflags "-s -w" -o "$tmp/deck-whatsapp-$arq" .
done
lipo -create -output "$saida/deck-whatsapp" "$tmp/deck-whatsapp-arm64" "$tmp/deck-whatsapp-amd64"
chmod 755 "$saida/deck-whatsapp"
echo "Ajudante do WhatsApp: $saida/deck-whatsapp"
