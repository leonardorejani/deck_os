#!/usr/bin/env bash
# Abre o Deck.app pelo LaunchServices, sem herdar o terminal.
# Por que não "open": aberto por "open" de dentro de um terminal (Terminal, iTerm, Orca...), o macOS 26 registra o item da
# barra de menus do Deck como se fosse desse app. Se ele estiver desligado em Ajustes do Sistema > Barra de Menus > Permitir
# na Barra de Menus, o ícone do Deck some. Pedir ao Finder é o mesmo que o duplo clique, sem esse vínculo.
# Uso: scripts/abrir-deck.sh [caminho/do/Deck.app]   (padrão: /Applications/Deck.app)
set -euo pipefail
app="${1:-/Applications/Deck.app}"
[ -d "$app" ] || { echo "Não achei o Deck em $app" >&2; exit 1; }
app="$(cd "$app" && pwd)"
osascript -e 'on run argv' -e 'tell application "Finder" to open (POSIX file (item 1 of argv))' -e 'end run' "$app"
