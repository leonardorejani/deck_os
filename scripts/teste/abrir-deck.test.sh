#!/usr/bin/env bash
# Prova que nada do projeto abre o Deck por "open" (o macOS 26 prende o ícone da barra ao terminal que abriu) e que
# abrir-deck.sh e build.sh --abrir pedem ao Finder (osascript). Os comandos de abrir são trocados por falsos: o "open"
# falso grava e falha, o "osascript" falso só grava. Roda no Mac e no Linux do CI (sem Xcode, sem Finder).
set -uo pipefail
raiz="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
falhas=0
confere() { if eval "$2"; then echo "ok   $1"; else echo "FALHOU $1"; falhas=$((falhas+1)); fi; }

# 1. nenhum script que abre o Deck chama "open", de nenhum jeito: "open -a", "/usr/bin/open", "| xargs open", "env open".
# Varre todo .sh do repo (hooks e scripts/teste inclusos, menos este arquivo) e o lefthook.yml (os YAML de CI rodam em Linux e têm texto corrido com "open").
chamaOpen() {
  grep -HnE '(^|[;&|(`]|[[:space:]])(/usr/bin/)?open([[:space:]]+(-|/|"|'"'"'|\$|~|[A-Za-z])|$)' "$@" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vE '^[^:]+:[0-9]+:.*(echo|printf|die|erro)[^|;&]*"[^"]*[[:space:]]open[[:space:]]'
}
listaAlvos() {
  find "$1" \( -name node_modules -o -name .build -o -name build -o -name .git -o -name worktrees -o -name Pods \) -prune -o \
    -type f \( -name '*.sh' -o -name 'lefthook.yml' \) -print | grep -v "scripts/teste/abrir-deck.test.sh"
}
alvos=(); while IFS= read -r f; do alvos+=("$f"); done < <(listaAlvos "$raiz")
confere "varreu build.sh, scripts e hooks (${#alvos[@]} arquivos)" '[ ${#alvos[@]} -ge 5 ]'
confere "nenhum script chama open" '! chamaOpen "${alvos[@]}"'

# 1b. o detector pega as formas escondidas (sem isso o teste pode passar sem proteger nada)
amostras="$tmp/amostras"; mkdir -p "$amostras"
i=0
for linha in 'open -a Deck' '/usr/bin/open -a Deck' 'echo /Applications/Deck.app | xargs open' 'cd x && open "$APP"' 'x; open /Applications/Deck.app' '$(open -g Deck)' 'ls | xargs -n1 open'; do
  i=$((i+1)); printf '#!/usr/bin/env bash\n%s\n' "$linha" > "$amostras/s$i.sh"
  confere "detector pega: $linha" 'chamaOpen "$amostras/s$i.sh" >/dev/null'
done
printf '#!/usr/bin/env bash\n# open -a Deck\necho "vamos open the door"\nopenssl x\nosascript -e x\n' > "$amostras/ok.sh"
confere "detector ignora comentário, texto e outros comandos" '! chamaOpen "$amostras/ok.sh"'

# 2. fakes no PATH
fakes="$tmp/fakes"; mkdir -p "$fakes" "$tmp/log"
cat > "$fakes/osascript" <<'F'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$FAKE_LOG/osascript.txt"
F
cat > "$fakes/open" <<'F'
#!/usr/bin/env bash
echo "open $*" >> "$FAKE_LOG/open.txt"; exit 1
F
chmod +x "$fakes"/*
export FAKE_LOG="$tmp/log"

# 3. abrir-deck.sh pede ao Finder, com o caminho exato (inclusive com espaço), e não chama open
mkdir -p "$tmp/Meu Deck.app"
PATH="$fakes:$PATH" bash "$raiz/scripts/abrir-deck.sh" "$tmp/Meu Deck.app"
confere "abrir-deck.sh usa o Finder" 'grep -q "tell application \"Finder\" to open" "$FAKE_LOG/osascript.txt"'
confere "abrir-deck.sh passa o caminho com espaço intacto" 'grep -qxF "$(cd "$tmp/Meu Deck.app" && pwd)" "$FAKE_LOG/osascript.txt"'
confere "abrir-deck.sh não chamou open" '[ ! -e "$FAKE_LOG/open.txt" ]'
PATH="$fakes:$PATH" bash "$raiz/scripts/abrir-deck.sh" "$tmp/nao-existe.app" 2>/dev/null
confere "app inexistente falha com código 1" '[ $? -eq 1 ]'

# 4. build.sh --abrir, numa cópia (não mexe no dist nem na config do dono), com o Xcode e o hdiutil de mentira
mkdir -p "$tmp/repo/scripts" "$tmp/repo/mac/App" "$tmp/home"
cp "$raiz/build.sh" "$tmp/repo/build.sh"; cp "$raiz/scripts/abrir-deck.sh" "$tmp/repo/scripts/"
# a assinatura tem teste próprio (assinatura.test.sh): aqui o app de mentira não tem o que assinar
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/repo/scripts/assinar-deck.sh"
for f in xcodegen hdiutil defaults; do printf '#!/usr/bin/env bash\nexit 0\n' > "$fakes/$f"; done
printf '#!/usr/bin/env bash\ncp -R "$1" "$2"\n' > "$fakes/ditto"
cat > "$fakes/xcodebuild" <<'F'
#!/usr/bin/env bash
mkdir -p Build/Products/Release 2>/dev/null; mkdir -p build/Build/Products/Release/Deck.app
echo "** BUILD SUCCEEDED **"
F
chmod +x "$fakes"/*
: > "$FAKE_LOG/osascript.txt"
HOME="$tmp/home" DECK_PASTA="$tmp/repo" PATH="$fakes:$PATH" bash "$tmp/repo/build.sh" --abrir > "$tmp/build.txt" 2>&1
confere "build.sh --abrir terminou" '[ $? -eq 0 ] || (cat "$tmp/build.txt"; false)'
confere "build.sh --abrir abriu o app compilado pelo Finder" 'grep -qxF "$tmp/repo/mac/App/build/Build/Products/Release/Deck.app" "$FAKE_LOG/osascript.txt"'
confere "build.sh --abrir não chamou open" '[ ! -e "$FAKE_LOG/open.txt" ]'
: > "$FAKE_LOG/osascript.txt"
HOME="$tmp/home" DECK_PASTA="$tmp/repo" PATH="$fakes:$PATH" bash "$tmp/repo/build.sh" > "$tmp/build2.txt" 2>&1
confere "build.sh sem --abrir não abre nada" '[ ! -s "$FAKE_LOG/osascript.txt" ] && [ ! -e "$FAKE_LOG/open.txt" ]'
confere "build.sh manda abrir pelo Finder, não pelo terminal" 'grep -q "Finder" "$tmp/build2.txt"'

[ "$falhas" -eq 0 ] && echo "abrir-deck: ok" || { echo "abrir-deck: $falhas falha(s)"; exit 1; }
