#!/usr/bin/env bash
# Prova do WhatsApp por QR (aparelho conectado) na bancada. Mostra o QR NESTE terminal, espera você ler no celular
# (WhatsApp > Aparelhos conectados > Conectar um aparelho), deixa a sessão guardada na pasta da bancada e conta
# quantas conversas com não lidas chegaram (só números, nunca nome nem texto). SÓ LEITURA: nada é enviado nem marcado como lido.
#
# Não é oficial e viola os termos do WhatsApp. Para sair: apague o aparelho "Deck (só leitura)" em Aparelhos conectados
# no celular, ou use "Apagar este aparelho" nos Ajustes do Deck.
#
# Uso: scripts/whatsapp-qr-prova.sh [--ligar-bancada] [--pasta <pasta-da-sessão>]
#   --ligar-bancada   depois de parear, põe a origem do WhatsApp em "qr" na config da BANCADA (nunca na do Deck de
#                     verdade), para ela voltar a conectar sozinha com a sessão guardada
#   --pasta           outra pasta de sessão (a padrão é a da bancada: ~/Library/Application Support/Deck Bancada/whatsapp-qr)
# Feche o Deck Bancada antes de parear: a sessão não pode ser aberta por dois processos ao mesmo tempo.
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
dados="$HOME/Library/Application Support/Deck Bancada"
pasta="$dados/whatsapp-qr"
ligar=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ligar-bancada) ligar=1 ;;
    --pasta) pasta="${2:?falta a pasta}"; shift ;;
    *) echo "Uso: scripts/whatsapp-qr-prova.sh [--ligar-bancada] [--pasta <pasta>]" >&2; exit 1 ;;
  esac
  shift
done

if pgrep -f "Deck Bancada.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "O Deck Bancada está aberto. Feche e rode de novo (a sessão não pode ter dois donos)." >&2
  exit 1
fi

bash "$raiz/helpers/whatsapp/build.sh" >/dev/null
ajudante="$raiz/helpers/whatsapp/build/deck-whatsapp"

echo "Sessão em: $pasta"
echo "Leia o QR no celular. Depois de conectar, o ajudante espera o histórico chegar (uns 45 s) e sai sozinho."
echo
"$ajudante" --prova --pasta "$pasta"

if [ ! -f "$pasta/pareado" ]; then
  echo "Não ficou sessão guardada (o QR não foi lido?). Rode de novo." >&2
  exit 1
fi
echo
echo "Sessão guardada. Com a bancada fechada, ela volta a conectar sozinha quando a origem do WhatsApp for QR."

if [ "$ligar" = 1 ]; then
  config="$dados/config.json"
  [ -f "$config" ] || { echo "A bancada ainda não tem config (abra o Deck Bancada uma vez). Depois ligue em Ajustes > Este Mac > WhatsApp." >&2; exit 1; }
  python3 - "$config" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c.setdefault("whatsapp", {})["origem"] = "qr"
json.dump(c, open(p, "w"), ensure_ascii=False, indent=2)
PY
  echo "Config da bancada: origem do WhatsApp agora é QR."
else
  echo "Para ligar na bancada: Ajustes > Este Mac > WhatsApp > Aparelho conectado (QR), ou rode de novo com --ligar-bancada."
fi
