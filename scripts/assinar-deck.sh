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
if [ -n "${DECK_ASSINATURA:-}" ]; then
  codesign --force --deep --sign "$DECK_ASSINATURA" --preserve-metadata=entitlements "$app"
else
  codesign --force --deep --sign - --preserve-metadata=entitlements -r="designated => identifier \"$id\"" "$app"
fi
codesign --verify --deep --strict "$app"
echo "Assinado: $(codesign -d -r- "$app" 2>&1 | grep '^designated')"
