# "Reconectando várias vezes" era reinstalação e prazo curto, não o canal

Data: 11/11/2026.

## O que aconteceu

O iPhone mostrava "Mac desconectado" com frequência. A suspeita era o canal (Wi-Fi, cabo, Bluetooth).
O `~/Library/Logs/Deck/deck.log` mostrou outra coisa: 17 aberturas do Deck.app em 11 horas (reinstalações e
reaberturas durante a construção, 8 delas em 17 minutos de teste), e a cada uma o iPhone ficou 7 a 14 s
sem o Mac. Nenhuma queda de canal sem causa externa (reinstalação, Mac dormindo, cabo puxado, iPhone
suspenso).

## Causa

Duas regras apertadas demais amplificavam qualquer tropeço:

- A página dava o Mac por sumido com 2 falhas (cerca de 2 s) e tinha tempo limite de 3 s por pedido. O
  estado leva até 2 s na primeira leitura depois que o Deck abre, e um pedido de 3,4 s apareceu no log.
- O estado do Mac esperava a fonte lenta inteira (até 2 s) toda vez que o cache dela vencia, e o selo do
  Dock do WhatsApp era lido depois do prazo das fontes, sem limite nenhum.

## Como resolver

Com o painel aberto, "Mac desconectado" só com 3 falhas seguidas e mais de 5 s sem resposta boa. Tempo
limite de 5 s. No Mac, fonte com valor guardado que venceu é esperada por 0,5 s e depois devolve o último
valor bom, e o selo do Dock entra no prazo das fontes.

## Como evitar

- Quedas de conexão: separar primeiro as aberturas do Deck.app (linha `deck: cabo e Bluetooth ligados`
  no log) das quedas com o Deck rodando, e conferir `pmset -g log` para o Mac dormindo.
- Tela de "sumiu" decide por tempo sem resposta, nunca por contagem de falhas sozinha.
- Leitura de fonte do Mac nunca roda fora do prazo do estado.
- O `deck.log` não registra o Wi-Fi/HTTPS: queda por Wi-Fi não aparece nele.
