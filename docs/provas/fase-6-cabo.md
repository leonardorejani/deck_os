# Prova da fase 6: o cabo

iPhone 15 Pro Max dele (`iPhone de teste`), app `com.leonardorejani.deck.iphone`, Mac rodando o `DeckServidor`
com uma config de teste (`/tmp`, uma tecla de comando que grava um arquivo temporário, nunca a config real).

## Prova técnica

O usbmuxd lista o iPhone por USB e recusa a conexão enquanto o app não escuta (código 3). Com o app aberto,
o `Connect` na porta 4975 (big endian) é aceito e o soquete vira o fio cru:

```
cabo: iPhone 10 no cabo: O app do Deck não está aberto no iPhone.
cabo conectado ao iPhone 10 pelo usbmux (porta 4975 do aparelho)
```

## Pareamento pela segunda via, estado ao vivo e tecla (log do Mac)

O app abre sem Mac guardado (`-prova-esquecer`), acha o Mac no cabo, digita os 6 dígitos que o Mac mostrou e
parear. Depois a página pede o estado a cada segundo e uma tecla do tipo comando é tocada:

```
cabo conectado ao iPhone 10 pelo usbmux (porta 4975 do aparelho)
cabo usbmux/10 POST /api/parear 200 5 ms
cabo usbmux/10 GET /api/estado 200 380 ms
cabo usbmux/10 GET /api/config 200 0 ms
cabo usbmux/10 GET /api/capa 200 0 ms
cabo usbmux/10 GET /api/estado 200 178 ms
cabo usbmux/10 POST /api/botao/gravar 200 57 ms
$ cat /tmp/deck-prova-cabo/tecla.txt
tecla executada em 18:43:32
```

Log do iPhone (`Documents/prova.log`):

```
cabo: Mac "MacBook Pro de Exemplo" conectado
PROVA_CABO etapa codigo mac=MacBook Pro de Exemplo
PROVA_CABO parear ok etapa=pronto
PROVA_ETAPA painel
PROVA_TECLA gravar clicou
```

A foto tirada pelo app mostra o relógio, o Spotify com a capa (que também vem pelo fio), as sessões esperando e
o selo de não lidas do WhatsApp, todos reais, e o aviso "Gravar arquivo: feito".

## Tirar e pôr o cabo

Simulado matando o `DeckServidor` (a conexão cai igual a um cabo puxado) e abrindo de novo 26 s depois:

```
iPhone  21:43:51 cabo: conexão com o Mac caiu          (a página mostra "Mac desconectado")
Mac     servidor reaberto
iPhone  21:44:04 cabo: Mac "MacBook Pro de Exemplo" conectado   (o painel volta sozinho, sem parear de novo)
```

Reabrir o app no iPhone também volta sozinho: o código fica no Keychain e o Mac conecta em até 2 s.

## O que ficou pendente

- Wi-Fi do iPhone desligado e modo avião: precisa dele no aparelho. O que já prova o cabo sem rede: o app não
  tem código de rede neste caminho (só o loopback do iPhone) e o log do Mac mostra os pedidos chegando por `usbmux/10`.
- Puxar e plugar o cabo de verdade (aqui foi simulado).
- O Bluetooth e a troca automática entre canais são da fase 7.

## Quem fala no cabo (correção da verificação)

Qualquer app do iPhone alcança a porta 4975 do loopback, então o app só confia em quem prova um segredo.
O iPhone manda um desafio (nonce sorteado) e o Mac responde com HMAC-SHA256 do nonce, usando o código de acesso
(iPhone pareado) ou os 6 dígitos do pareamento em curso (iPhone sem pareamento, antes de mandar os dígitos).
Sem prova, a conexão não vira o Mac, não recebe pedido e não troca uma conexão já provada. Prova no aparelho:
pareamento pelo cabo com os dígitos (`PROVA_CABO parear ok etapa=pronto`) e reconexão pareada
(`cabo: Mac "MacBook Pro de Exemplo" conectado`, desafio de acesso com o código do Keychain).
Limite conhecido: o rodízio do código precisa deixar o Mac provar com o código que o iPhone ainda guarda
(aceitar o anterior por um tempo), senão um iPhone que perdeu a resposta com o código novo não reconecta pelo cabo.
