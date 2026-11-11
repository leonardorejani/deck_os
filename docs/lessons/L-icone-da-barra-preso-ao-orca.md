# Ícone da barra de menus preso ao app que abriu o Deck

Data: 11/11/2026.

## O que aconteceu

O Deck rodava (servindo o iPhone pelo cabo), mas o ícone nunca aparecia na barra de menus, mesmo
com o Deck ligado em Ajustes do Sistema > Barra de Menus > Permitir na Barra de Menus. A chave
`NSStatusItem VisibleCC Item-0` do Deck voltava a 0 a cada abertura.

## Causa

Durante a construção, o Deck foi aberto várias vezes de dentro de um terminal do Orca. O macOS 26
registrou o item da barra do Deck como se fosse do Orca: em
`~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`,
chave `trackedApplications`, a entrada do Orca (`com.stablyai.orca`, `isAllowed: False`) listava
`com.leonardorejani.deck` em `menuItemLocations`. Com o Orca desligado, o ícone do Deck some.
Abrir pelo Finder depois não desfaz o vínculo, e o Control Center regrava o arquivo se for editado.

## Como resolver

Ligar o app "dono" (aqui, o Orca) em Permitir na Barra de Menus. O ícone do Deck aparece na hora.

## Como evitar

- Abrir o Deck instalado pelo Finder, Spotlight ou `osascript -e 'tell application "Finder" to open POSIX file "/Applications/Deck.app"'`, nunca por `open` de dentro de um terminal do Orca.
- Ícone sumido: conferir `trackedApplications` antes de mexer no código. Desde o #36, reabrir o
  Deck abre os Ajustes e o aviso de ícone escondido aparece no topo.
