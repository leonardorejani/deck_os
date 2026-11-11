#!/usr/bin/env bash
# Primeira instalação do app nativo do Deck no iPhone (conta grátis da Apple, sem abrir o Xcode depois).
# Confere o Xcode, a conta da Apple no Xcode e o iPhone, e chama ios/instalar.sh.
# Depois disso o Deck do Mac renova o app sozinho a cada 5 dias (Ajustes > Conectar iPhone).
# Uso: ./instalar-iphone.sh
set -uo pipefail
raiz="$(cd "$(dirname "$0")" && pwd)"
falha() { echo "Parou: $1" >&2; [ $# -gt 1 ] && echo "  $2" >&2; exit 1; }

xcodebuild -version >/dev/null 2>&1 \
  || falha "o Xcode não está instalado ou não está pronto." "Instale o Xcode pela App Store, abra uma vez e aceite a licença. Depois rode de novo."
command -v xcodegen >/dev/null || falha "falta o xcodegen." "Rode: brew install xcodegen"

defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null | grep -q identifier \
  || falha "não achei nenhuma conta da Apple no Xcode." "Abra o Xcode > Settings > Apple Accounts, toque em + e entre com sua Apple ID. Depois rode de novo."

tabela="$(xcrun devicectl list devices 2>/dev/null)"
aparelho="$(echo "$tabela" | grep -E '(^|[^a-z])(available|connected)' | grep -m1 -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' || true)"
[ -n "$aparelho" ] || falha "não achei o iPhone." "Ligue o iPhone no cabo, desbloqueie e toque em Confiar neste computador. Depois rode de novo."

trava="$(xcrun devicectl device info lockState --device "$aparelho" 2>/dev/null | tr 'A-Z' 'a-z')"
case "$trava" in
  *"passcoderequired: true"*) falha "o iPhone está bloqueado." "Desbloqueie o iPhone e rode de novo." ;;
esac

echo "Instalando no iPhone (a primeira vez demora uns minutos)..."
saida="$(bash "$raiz/ios/instalar.sh" "$aparelho" --abrir 2>&1)" || true
echo "$saida"
echo "$saida" | grep -q "App installed" \
  || falha "a instalação não terminou." "Veja a mensagem acima. Se for 'No Accounts', entre de novo em Xcode > Settings > Apple Accounts."

# O Deck do Mac lê isto: onde está o repo e quando o app foi instalado (a renovação conta 5 dias daqui).
pasta="${DECK_PASTA:-${raiz%%/.claude/worktrees/*}}"
mkdir -p "$HOME/Library/Application Support/Deck"
arquivo="$HOME/Library/Application Support/Deck/renovacao"
defaults write "$arquivo" pasta -string "$pasta"
defaults write "$arquivo" instaladoEm -date "$(date -u '+%Y-%m-%d %H:%M:%S +0000')"

echo
echo "Pronto. O app está no iPhone."
echo "Primeira vez: no iPhone, Ajustes > Geral > VPN e Gerenciamento de Dispositivo > confie no seu desenvolvedor."
echo "O Deck do Mac renova o app sozinho a cada 5 dias, com o iPhone no cabo ou no mesmo Wi-Fi."
