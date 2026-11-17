#!/usr/bin/env bash
# Varredura de 16/11/2026: repo público sem dado real, sem binário versionado e com uma versão só. Roda no Mac e no Linux do CI.
set -uo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$raiz"
falhas=0
confere() { if eval "$2"; then echo "ok   $1"; else echo "FALHOU $1"; falhas=$((falhas+1)); fi; }

confere "nenhum celular real nos arquivos versionados" '! git grep -qE "98409-?7902" -- . ":!scripts/teste/seguranca-build.test.sh"'
confere "nenhum binário do helper do WhatsApp no git" '[ -z "$(git ls-files helpers/whatsapp/whatsapp)" ]'
confere "o binário solto do helper está no .gitignore" 'git check-ignore -q helpers/whatsapp/whatsapp'
confere "o build do helper usa -trimpath" 'grep -q -- "-trimpath" helpers/whatsapp/build.sh'
v="$(tr -d '[:space:]' < VERSAO 2>/dev/null)"
confere "VERSAO existe e tem o formato N.N" '[[ "$v" =~ ^[0-9]+\.[0-9]+$ ]]'
confere "o project.yml do Mac usa a versão do VERSAO" 'grep -q "MARKETING_VERSION: \"$v\"" mac/App/project.yml'
confere "o project.yml do iPhone usa a versão do VERSAO" 'grep -q "MARKETING_VERSION: \"$v\"" ios/project.yml'
for s in build.sh scripts/bancada.sh ios/instalar.sh; do
  confere "$s lê o VERSAO e passa a versão ao xcodebuild" 'grep -q "VERSAO" "$s" && grep -q "MARKETING_VERSION=" "$s"'
done
confere "nenhum script fixa a versão na mão" '! grep -nE "^versao=\"[0-9]" build.sh scripts/bancada.sh ios/instalar.sh'

[ "$falhas" = 0 ] && echo "seguranca-build: ok" || { echo "seguranca-build: $falhas falhas"; exit 1; }
