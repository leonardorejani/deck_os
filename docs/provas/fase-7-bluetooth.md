# Prova da fase 7: o Bluetooth

iPhone 15 Pro Max dele (`iPhone de teste`), app `com.leonardorejani.deck.iphone`, Mac rodando o `DeckServidor`.

## Prova técnica: a vazão medida

O Mac é o periférico (`CBPeripheralManager`) e anuncia o serviço do Deck. O iPhone é a central: escreve os pedidos
na característica de pedido (sem resposta) e recebe as respostas por notificação. A medida roda sobre o fio cru
(antes da criptografia), com `DeckServidor --bt-vazao` e o app aberto com `-prova-bt-vazao`. Log do iPhone
(`Documents/prova.log`), duas rodadas seguidas:

```
bluetooth: conectado (pacote de até 512 bytes)
VAZAO 4096 bytes:   ping medio 65 ms (max 87 ms),  descida 22.0 KB/s em 0.18 s, subida 22.1 KB/s em 0.18 s
VAZAO 32768 bytes:  ping medio 59 ms (max 61 ms),  descida 28.8 KB/s em 1.11 s, subida 26.0 KB/s em 1.23 s
VAZAO 131072 bytes: ping medio 59 ms (max 60 ms),  descida 23.0 KB/s em 5.55 s, subida 29.5 KB/s em 4.35 s
---
VAZAO 4096 bytes:   ping medio 59 ms,  descida 21.9 KB/s, subida 16.8 KB/s
VAZAO 32768 bytes:  ping medio 65 ms,  descida 26.0 KB/s, subida 21.4 KB/s
VAZAO 131072 bytes: ping medio 173 ms (max 504 ms), descida 28.3 KB/s, subida 24.9 KB/s
```

Resumo: pacote de 512 bytes, latência de ida e volta de uns 60 ms e vazão de uns 25 KB/s nos dois sentidos.

O que isso decide para este canal:

- **Estado, config, agenda e tecla:** 2 a 4 KB por resposta, de 0,1 a 0,2 s. O painel que pede o estado a cada 1 s cabe.
- **Capa do Spotify:** uma capa de 640 px passa de 50 KB e levaria 2 s ou mais, parando o resto. No Bluetooth o Mac
  manda a capa reduzida a 200 px em JPEG com qualidade 0,6 (de 8 a 15 KB, até 0,6 s), só quando a faixa muda.
  Sem como reduzir, o Mac responde 404 e o painel fica sem capa. Nada de imagem grande pelo ar.
- **Ícones:** não passam pelo canal. Os das teclas e do painel moram dentro do app (`ios/Pagina/icones`).
- **Nome do Mac:** o macOS não coloca o nome no anúncio. O iPhone só o conhece depois de conectar, então na primeira
  vez ele conecta um instante em cada Mac novo da lista só para ler o nome e solta.

## Pareamento, painel e tecla pelo Bluetooth, no iPhone dele

O app abre sem Mac guardado (`-prova-esquecer`) e sem o canal do cabo (`-prova-sem-cabo`). O iPhone não estava no
cabo nesta rodada (o Mac dizia `cabo: Nenhum iPhone no cabo.`), então só havia o Bluetooth. O Mac roda
`DeckServidor --config` (config de teste em `/tmp`, uma tecla que grava um arquivo) com `--bt-permitir`.
Duas rodadas de pareamento, os 6 dígitos nas duas pontas:

```
iPhone  00:56:28 PROVA_BT codigo 271 740 etapa=confirmar mac=MacBook Pro de Exemplo
Mac     bluetooth 737A3C86: iPhone quer parear, código 271740
iPhone  00:57:13 PROVA_BT codigo 419 246 etapa=confirmar mac=MacBook Pro de Exemplo
Mac     bluetooth 737A3C86: iPhone quer parear, código 419246
iPhone  PROVA_BT confirmar ok etapa=pronto
Mac     bluetooth 737A3C86: conexão cifrada
```

Depois, o painel vivo e a tecla (log do Mac, tudo por `bluetooth/`, e o arquivo que a tecla grava):

```
cabo bluetooth/737A3C86 GET /api/estado 200 149 ms
cabo bluetooth/737A3C86 GET /api/config 200 0 ms
cabo bluetooth/737A3C86 GET /api/capa 200 7 ms
cabo bluetooth/737A3C86 POST /api/botao/gravar 200 46 ms
$ cat /tmp/deck-bt/tecla.txt
tecla executada em 21:57:17
iPhone  PROVA_TECLA gravar clicou
iPhone  PROVA_MONITOR canal=bluetooth pagina={"offline":false,"chip":""}   (a cada 2 s, 60 vezes)
```

Reabrir o app já pareado conecta sozinho e mostra o aviso do canal (`"chip":"Pelo Bluetooth"`). A foto da tela (relógio,
Spotify com a capa pequena, sessões esperando, teclas e o selo do WhatsApp) saiu do app: `Documents/seq-2.png`.

## Segurança do canal

O Bluetooth é aberto ao ar, então nada passa em texto puro. Curve25519 para as chaves e ChaChaPoly para cada
registro, com contador de nonce por direção (registro repetido, fora de ordem ou adulterado derruba a conexão).
O código de acesso, que viaja em todo pedido, nunca fica exposto.

- **Pareamento (iPhone novo):** o Mac se compromete com a chave dele (hash) antes de ver a do iPhone. Os dois
  derivam os mesmos 6 dígitos da conversa inteira e a pessoa confere nas duas telas. Quem está no meio e troca uma
  chave deixa os dois lados com códigos diferentes, e o compromisso impede de sortear chaves até os dígitos baterem.
  O código de acesso só segue depois de Permitir no Mac e "São iguais" no iPhone, já pelo fio cifrado.
- **Reconexão (iPhone já pareado):** cada lado prova que conhece o código de acesso (HMAC sobre a conversa). O Mac
  confere contra todos os códigos que valem (hoje o atual, e o anterior na folga do rodízio assim que ele entrar).
- Um pareamento por vez na tela do Mac, e no máximo 4 sessões.

## Testes que provam sem rádio

`swift test` nos dois pacotes (Mac e Linux): vetor de ouro dos 6 dígitos igual nos dois lados (conferido também com
`hashlib` em Python), pareamento com os mesmos dígitos, recusa em cada lado, chave trocada no meio, código errado,
registro adulterado e repetido, a sessão inteira com o roteador de verdade, reconexão, troca cabo e Bluetooth.
Teste que falhava antes do conserto: puxar o cabo no meio de uma leitura devolvia `O cabo foi desconectado.` à
página, e agora a leitura é repetida no Bluetooth (tecla não se repete, para não apertar duas vezes).

## O que não foi provado no aparelho

- **Puxar o cabo de verdade no meio do uso:** o iPhone não estava plugado. A troca cabo para Bluetooth está provada em
  teste com o cabo de verdade (soquete no loopback, como o usbmuxd) e o fio do Bluetooth em memória, incluindo a
  leitura que estava indo pelo cabo ser repetida. No aparelho falta plugar, abrir o app com `-prova-cabo-sai-em 30`
  (derruba o cabo como se fosse puxado) ou puxar o cabo, e ver `canal=cabo` virar `canal=bluetooth` sem `offline`.
- **Modo avião e Wi-Fi desligado:** o app não tem código de rede nesse caminho, mas ninguém ligou o modo avião.
- **Conferência na tela do Mac:** a tela de Permitir é do app do Mac (outra frente). O Nucleo expõe `decidir`
  (iPhone e código) e o `DeckServidor` usa o teclado.

## Permissões que pedem o toque dele

- iPhone: o aviso "Deck quer usar o Bluetooth" aparece na primeira vez que o app procura (ou ao abrir já pareado).
  Aceitar uma vez. Sem isso, a lista de Macs fica vazia e o app avisa "O Deck não tem permissão de Bluetooth".
- iPhone com o Bluetooth desligado (Centro de Controle ou modo avião): a procura avisa "O Bluetooth do iPhone está
  desligado. Ligue no Centro de Controle."
- Mac: o `DeckServidor` já traz o `NSBluetoothAlwaysUsageDescription` dentro do executável. O app do Mac precisa do
  mesmo texto no Info.plist dele (ver o PR).
