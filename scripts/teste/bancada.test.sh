#!/usr/bin/env bash
# Prova que o Deck Bancada não encosta no Deck de verdade: identificador, nome e porta próprios, e nenhum caminho ou
# serviço do Deck real escrito na mão no código do Mac (tudo passa por Variante). Roda no Mac e no Linux do CI.
set -uo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
falhas=0
confere() { if eval "$2"; then echo "ok   $1"; else echo "FALHOU $1"; falhas=$((falhas+1)); fi; }
yml="$raiz/mac/App/project.yml"

confere "a bancada tem identificador próprio" 'grep -q "PRODUCT_BUNDLE_IDENTIFIER: com.leonardorejani.deck.bancada$" "$yml"'
confere "a bancada se chama Deck Bancada" 'grep -q "PRODUCT_NAME: Deck Bancada$" "$yml"'
confere "a bancada tem ícone próprio" '[ -f "$raiz/mac/App/Recursos/Assets.xcassets/AppIconBancada.appiconset/icone-1024.png" ] && grep -q "ASSETCATALOG_COMPILER_APPICON_NAME: AppIconBancada" "$yml"'
confere "a porta da bancada é 4791" 'grep -q "portaDaBancada = 4791" "$raiz/mac/Nucleo/Variante.swift"'
# nenhum caminho nem serviço do Deck real fora de Variante.swift
fora() { grep -rnE 'Application Support/Deck|Logs/Deck/|"com\.leonardorejani\.deck\.(spotify|token-claude)"' "$raiz/mac/Nucleo" "$raiz/mac/App" --include='*.swift' \
  | grep -v "Variante.swift" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(///|//)' | grep -vE '/Testes?/|/Fotos/'; }
confere "nenhum caminho ou serviço do Deck real fica fixo no código" '[ -z "$(fora)" ]'
confere "o script da bancada não abre o app" '! grep -vE "^[[:space:]]*#|echo" "$raiz/scripts/bancada.sh" | grep -qE "(^|[;&|[:space:]])(/usr/bin/)?open[[:space:]]"'
confere "o script da bancada instala fora de /Applications" '! grep -qE "(^|[\" ])/Applications/" "$raiz/scripts/bancada.sh" && grep -q "Applications/Deck Bancada.app" "$raiz/scripts/bancada.sh"'

[ "$falhas" = 0 ] && echo "bancada: ok" || { echo "bancada: $falhas falhas"; exit 1; }
