#!/usr/bin/env bash
# Copia a página do painel para ios/Pagina, que o app carrega de dentro do pacote.
# A origem é sempre o painel/ deste mesmo repo (a raiz de onde o script está), nunca o de outra worktree.
set -euo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
origem="$raiz/painel"
destino="$raiz/ios/Pagina"

[ -f "$origem/index.html" ] || { echo "erro: $origem/index.html não existe" >&2; exit 1; }
rm -rf "$destino"
mkdir -p "$destino"
rsync -a --exclude 'teste/' --exclude '*.md' "$origem/" "$destino/"
estado="$(git -C "$raiz" rev-parse --short HEAD 2>/dev/null || echo '?')"
git -C "$raiz" diff --quiet HEAD -- painel 2>/dev/null || estado="$estado com alterações ainda não commitadas"
echo "painel empacotado de $origem ($estado)"
[ -f "$destino/index.html" ] || { echo "erro: index.html não foi para $destino" >&2; exit 1; }
