#!/usr/bin/env bash
# Compila o Deck.app do Mac em Release (assinatura ad hoc com requisito estável, sem conta paga) e gera dist/Deck-1.1.dmg
# com o app e um atalho para Aplicativos. Também grava onde está este repo para o Deck renovar o app do iPhone.
# Uso: ./build.sh [--abrir]    (--abrir abre o app recém-compilado pelo Finder, nunca por "open": ver scripts/abrir-deck.sh)
set -euo pipefail
raiz="$(cd "$(dirname "$0")" && pwd)"
abrir=0
for a in "$@"; do
  case "$a" in
    --abrir) abrir=1 ;;
    *) echo "Uso: ./build.sh [--abrir]" >&2; exit 1 ;;
  esac
done
versao="1.1"
numero="$(git -C "$raiz" rev-list --count HEAD 2>/dev/null || echo 1)"
dmg="$raiz/dist/Deck-$versao.dmg"

for f in xcodebuild xcodegen hdiutil; do
  command -v "$f" >/dev/null || { echo "Falta o $f. Instale o Xcode e rode: brew install xcodegen" >&2; exit 1; }
done

echo "Compilando o Deck $versao ($numero)..."
cd "$raiz/mac/App"
xcodegen generate --quiet
xcodebuild -project Deck.xcodeproj -scheme Deck -configuration Release -derivedDataPath build \
  MARKETING_VERSION="$versao" CURRENT_PROJECT_VERSION="$numero" CODE_SIGN_IDENTITY="-" build \
  | grep -E "error:|\*\* BUILD" | tail -5
app="$raiz/mac/App/build/Build/Products/Release/Deck.app"
[ -d "$app" ] || { echo "A compilação não gerou o Deck.app" >&2; exit 1; }
# Ajudante do WhatsApp por QR (Go): vai dentro do app, em Contents/Helpers, antes da assinatura. Sem Go neste Mac o Deck
# sai sem ele e a opção de QR avisa que não está disponível (o resto do Deck não muda).
if bash "$raiz/helpers/whatsapp/build.sh" "$app/Contents/Helpers"; then :; else
  [ "$?" = 3 ] || { echo "O ajudante do WhatsApp não compilou" >&2; exit 1; }
fi
# Requisito de assinatura estável: sem isso cada build é "outro app" para o macOS e perde Acessibilidade e Acesso Total ao Disco.
bash "$raiz/scripts/assinar-deck.sh" "$app"

echo "Montando o .dmg..."
palco="$(mktemp -d)"
trap 'rm -rf "$palco"' EXIT
ditto "$app" "$palco/Deck.app"
ln -s /Applications "$palco/Aplicativos"
mkdir -p "$raiz/dist"
rm -f "$dmg"
hdiutil create -quiet -volname "Deck" -srcfolder "$palco" -format UDZO -ov "$dmg"

# O Deck renova o app do iPhone a partir desta pasta. Numa worktree vale a pasta principal (a worktree some depois do merge).
pasta="${DECK_PASTA:-${raiz%%/.claude/worktrees/*}}"
mkdir -p "$HOME/Library/Application Support/Deck"
defaults write "$HOME/Library/Application Support/Deck/renovacao" pasta -string "$pasta"

echo "Pronto: $dmg (versão $versao, compilação $numero)"
echo "Abra o .dmg e arraste o Deck para Aplicativos. Na primeira abertura: Ajustes do Sistema > Privacidade e Segurança > Abrir mesmo assim."
echo "Abra o Deck pelo Finder ou pelo Spotlight, nunca por \"open\" no terminal (o ícone da barra de menus pode sumir)."
if [ "$abrir" = 1 ]; then bash "$raiz/scripts/abrir-deck.sh" "$app"; fi
