#!/usr/bin/env bash
# Assina o Deck.app com um requisito estável, para o macOS não perder as permissões (Acessibilidade, Acesso Total ao
# Disco) a cada build novo. Assinatura ad hoc pura tem o requisito "cdhash X", e o cdhash muda a cada compilação:
# o macOS guarda a permissão amarrada a esse requisito, então o interruptor continua ligado nos Ajustes do Sistema
# mas o app novo não é mais "aquele". Aqui o requisito vira só o identificador do app.
# Uso: scripts/assinar-deck.sh <Deck.app>
#   DECK_ASSINATURA="<identidade do Keychain>"  usa um certificado de verdade (Apple Development, Developer ID...), cujo
#                                               requisito padrão já é estável (identificador + certificado)
set -euo pipefail
app="${1:?Uso: scripts/assinar-deck.sh <Deck.app>}"
[ -d "$app" ] || { echo "Não achei $app" >&2; exit 1; }
id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
# Código de ajudante em Contents/Helpers (o do WhatsApp por QR) é assinado antes, com o identificador dele. Com --deep o
# requisito do app (o identificador do Deck) seria imposto ao ajudante e o selo do app ficaria inválido.
if [ -d "$app/Contents/Helpers" ]; then
  for h in "$app"/Contents/Helpers/*; do
    [ -f "$h" ] || continue
    codesign --force --sign "${DECK_ASSINATURA:--}" -i "$id.$(basename "$h")" "$h"
  done
  fundo=""
else
  fundo="--deep"
fi
if [ -n "${DECK_ASSINATURA:-}" ]; then
  codesign --force $fundo --sign "$DECK_ASSINATURA" --preserve-metadata=entitlements "$app"
else
  codesign --force $fundo --sign - --preserve-metadata=entitlements -r="designated => identifier \"$id\"" "$app"
fi
codesign --verify --deep --strict "$app"
echo "Assinado: $(codesign -d -r- "$app" 2>&1 | grep '^designated')"
