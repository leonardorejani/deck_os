# Prova da fase 4: PWA no iPhone

Fase 4 do `PLANO.md`: manifesto e ícone, tela cheia, service worker, tela sempre acesa, deslocamento contra queima de
tela e o pareamento pelo QR com a instalação do certificado. O Deck do Mac serve tudo isso a partir de `painel/`.

## O que foi feito

| Peça | Onde | O que faz |
|---|---|---|
| Manifesto | `painel/manifest.webmanifest` | `Deck`, `display: standalone`, `id` e `scope` `/`, `start_url` `/?origem=app`, cores da abertura iguais ao fundo do painel (`#0E0E0E`), ícones 192 e 512 comuns e maskable |
| Ícones | `painel/icones/pwa/` | Gerados de `prototipo/icones/deck.png` com o `gerar-icones.sh` da tatile, mais o `apple-touch-icon` de 180 px |
| Service worker | `painel/sw.js` | Guarda só a casca (HTML, CSS, JS e ícones). Abre na hora, mesmo com o Mac desligado. A API (`/api/*`) e o `/ca.crt` nunca passam por ele nem entram em cache |
| Mac desconectado | `painel/deck.js` (já existia) | Com o Mac fora do ar a página abre do cache, o canal não responde e a tela fecha em "Mac desconectado". Volta sozinha quando o Mac volta |
| Tela acesa | `painel/pwa.js` | Wake Lock pedido ao abrir e de novo toda vez que a página volta à tela. Sem ele (negado ou navegador sem a API), avisa para desligar o bloqueio automático |
| Queima de tela | `painel/pwa.js`, `painel/deck.css` | A moldura anda 1 a 2 px a cada 3 min (SPEC 11), devagar, sem salto |
| Pareamento pelo QR | `painel/pareamento.js` | O link do QR abre o passo a passo do certificado (rota `/ca.crt`, SPEC 8), depois troca os 6 dígitos pelo código de acesso e entra no painel |
| Digitar o código | `painel/pareamento.js` | A tela "Deck não pareado" ganha o botão "Digitar o código do Mac". Serve para o ícone da Tela de Início, que nasce com os dados à parte do Safari |

No app nativo (`window.DeckCanal`) nada disso liga: sem service worker, sem Wake Lock (a casca cuida da tela acesa) e sem
tela de certificado (o pareamento é por cabo e Bluetooth). O deslocamento contra queima de tela vale nos dois.

### Fluxo do pareamento

1. No Mac: Ajustes, Conectar iPhone. O QR leva `https://<mac>.local:4777/#parear=<6 dígitos>&certificado=<link>`.
2. O iPhone lê o QR e abre o Safari. Antes de confiar no certificado o Safari avisa que a conexão não é privada:
   Mostrar detalhes, Visitar este site.
3. A página abre a tela "Instale o certificado do Deck": Baixar certificado, Permitir, Ajustes > Perfil Transferido > Instalar,
   Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados > ligar o Deck, voltar e tocar em Continuar.
   O certificado baixado é sempre o `/ca.crt` do mesmo endereço, nunca um link vindo do fragmento.
4. Continuar troca os 6 dígitos por `POST /api/parear`, guarda o código de acesso e mostra o painel.
5. No Safari do iPhone aparece ainda "iPhone conectado" com Compartilhar > Adicionar à Tela de Início.
6. Se o código do QR venceu ou errou, a tela pede os 6 dígitos que o Mac mostra. Se o Mac estava fora do ar, volta ao
   certificado com o aviso e o mesmo QR segue valendo (falha de rede não gasta o código).

Os 6 dígitos nunca ficam na barra de endereço: a página tira o fragmento da URL ao ler. Recarregar a aba no meio do
passo a passo volta ao mesmo passo (o pendente fica só na sessão da aba).

## Prova (11/11/2026)

### 1. Auditor do PWA da tatile

```
$ node ~/.claude/skills/tatile/modulos/pwa/scripts/auditar.mjs painel --sem-cache
arquivos: 28
resumo: 0 erros, 2 avisos, 2 dicas
  I01 aviso  sem botão próprio de instalar (beforeinstallprompt)
  N09 aviso  viewport-fit=cover sem env(safe-area-inset-*)
  D01 dica   sem screenshots no manifesto
  D02 dica   sem shortcuts no manifesto
```

Antes da fase 4 ele saía com 2 erros (M01 sem manifesto, S01 sem service worker). Os 4 que sobram ficam como estão:
I01 é para Android e desktop (o iPhone instala pelo Compartilhar e a tela já diz isso), N09 porque o painel desenha o próprio
espaço seguro, calibrado no 15 Pro Max (mexer seria refazer um layout aprovado), D01 e D02 só enfeitam o convite do Chrome.
O auditor da tatile para a tela (`auditar.mjs painel`) segue com 0 erros e o mesmo aviso de antes (`espaco-solto`, `right: -7px`).

### 2. Chrome de verdade contra o Mac de mentira (`painel/teste/pwa.teste.mjs`)

Roda no `node painel/teste/rodar.mjs`, junto com os outros arquivos de teste do painel (398 verificações, todas OK).
O arquivo novo cobre 6 grupos, cada linha é uma verificação:

- manifesto: nome, `standalone`, `id`, escopo, `start_url`, cores, ícones 192 e 512 comuns e maskable, cada ícone responde 200 como PNG
- casca: o que o `index.html` carrega está na lista do `sw.js` e cada arquivo da lista existe (29 arquivos)
- service worker: instala, ativa e controla a página depois de recarregar. Um cache só (`deck-casca-v1`), a casca inteira dentro,
  nenhuma resposta de `/api/*` e nenhum `/ca.crt`, nem depois de vários passos do laço
- derrubar o Mac: o servidor é fechado de verdade, a página recarrega, abre na hora, a tela fecha em "Mac desconectado" com o nome
  do Mac guardado, o endereço do ícone (`/?origem=app`) também abre, a API falha de verdade (não vem do cache) e, ao religar o
  servidor, o painel reconecta sozinho
- tela acesa: pedida ao abrir, não pedida com a página escondida, pedida de novo ao voltar, nunca em dobro. Negada ou sem a API,
  o aviso manda desligar o bloqueio automático, e o toque tenta de novo
- queima de tela: padrão de 3 min, e a tela passa por 4 ou mais posições, todas a até 2 px do centro
- pareamento: o link do QR abre o passo a passo (com o `/ca.crt`), o código sai da barra de endereço, recarregar volta ao mesmo passo,
  Continuar pareia (o Mac recebeu os 6 dígitos uma vez) e guarda o código, em pé também cabe, no Safari do iPhone aparece a tela de
  Tela de Início, link sem certificado pareia direto, código errado cai na tela do código com o motivo, menos de 6 dígitos nem sai do
  aparelho, "Deck não pareado" ganha o botão e o laço volta a andar depois de parear, Mac fora do ar volta ao certificado e o mesmo QR
  serve quando ele volta
- app nativo (`window.DeckCanal`): nenhuma tela de certificado, service worker não registrado, nenhum Wake Lock

O teste falha antes da fase 4 e passa depois. Rodado com o `painel/` da main (87af926) e o mesmo arquivo de teste:

```
FALHA pwa.teste.mjs quebrou: Unexpected token 'ã', "não achei" is not valid JSON     (o manifesto não existe)
FALHOU: 1 verificação(ões)
```

Com a fase 4:

```
== pwa.teste.mjs
...
tudo certo
```

### 3. Deck.app real (build Debug desta branch), 11/11/2026

O `Deck.app` da branch foi compilado pelo `xcodebuild` e o pacote dele leva a página nova
(`Contents/Resources/painel/` com `manifest.webmanifest`, `sw.js`, `pwa.js`, `pareamento.js`, `icones/pwa/` e sem `teste/`).
Subiu com `open -g -n`, sem janela. O `HOME` trocado não vale para a config (o app usa o diretório do usuário), então ele leu a
config de verdade, achou a 4777 ocupada pelo Deck instalado e subiu na 4778. Foi derrubado depois da prova e o instalado seguiu de pé.
A config não foi tocada (mesma data de antes).

```
$ curl -sk -D - https://localhost:4778/manifest.webmanifest
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Cache-Control: no-cache
{'id': '/', 'name': 'Deck', 'display': 'standalone', 'start_url': '/?origem=app', 'scope': '/', 'theme_color': '#0E0E0E'}
icones: icones/pwa/icon-192.png icones/pwa/icon-512.png icones/pwa/icon-maskable-192.png icones/pwa/icon-maskable-512.png

$ curl -sk -D - https://localhost:4778/sw.js
HTTP/1.1 200 OK
Content-Type: text/javascript; charset=utf-8
Cache-Control: no-cache

$ curl -sk -D - https://localhost:4778/ca.crt
HTTP/1.1 200 OK
Content-Type: application/x-x509-ca-cert
Content-Disposition: attachment; filename="Deck.crt"
Cache-Control: no-cache
subject=CN=Deck   notAfter=Nov  7 20:34:18 2036 GMT

$ curl --cacert ca.crt --resolve MacBook-Pro-de-Exemplo.local:4778:127.0.0.1 https://MacBook-Pro-de-Exemplo.local:4778/manifest.webmanifest
com o CA do Deck: HTTP 200
sem o CA: curl sai com código 60 (certificado não confiável)

$ curl -sk https://localhost:4778/api/estado
HTTP 401 (sem código de acesso)
icones/pwa/icon-192.png, icon-512.png, icon-maskable-512.png, apple-touch-icon-180.png: HTTP 200 image/png
pwa.js, pareamento.js: HTTP 200 text/javascript
```

Chrome headless contra esse mesmo Deck.app (HTTPS, com `--ignore-certificate-errors` porque o Chrome do teste não tem o CA):

```
service worker ativo e controlando a página no Deck.app real (HTTPS)
cache: deck-casca-v1 29 arquivos, API guardada: 0 , ca.crt guardado: false
manifesto visto pelo Chrome: ["Deck","standalone",4]
Deck.app no ar: estado da tela = tela sem-acesso            (o código de acesso do teste era falso, então o Mac respondeu 401)
--- Deck.app encerrado (kill do processo da branch), página recarregada ---
Deck.app derrubado, página recarregada: {"titulo":"Deck","op":"1","txt":"Mac desconectado Seu Mac Confira se ele está ligado e no mesmo Wi-Fi."}
```

### 4. O resto da verificação

- `swift test --package-path mac`: 267 testes, 0 falhas. `swift test --package-path ios/Pacote`: 101 testes, 0 falhas.
- `xcodebuild test` do app do Mac: 172 testes, 0 falhas, `** TEST SUCCEEDED **`.
- Linux (Docker `swift:6.2` no runner Linux): `mac` 233 testes, `ios/Pacote` 79 testes, 0 falhas.
- Esta fase não muda Swift. O que o `Deck.app` ganha é só a pasta `painel/` com os arquivos novos.

## Teste final no iPhone dele (pendente, precisa da mão dele)

Nada abaixo foi feito. É o teste da prova 0.2 (`docs/provas/0.2-pwa.md`), agora com o Deck de verdade. iPhone e Mac no mesmo Wi-Fi.

1. No Mac: abra o Deck, Ajustes > Conectar iPhone. Deixe o QR na tela.
2. No iPhone: abra a Câmera e leia o QR. O Safari abre e avisa que a conexão não é privada. Toque em Mostrar detalhes e em
   Visitar este site. Tem que aparecer "Instale o certificado do Deck".
3. Toque em Baixar certificado e em Permitir. Abra Ajustes > Perfil Transferido > Instalar (pede o código do iPhone).
4. Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados > ligue o Deck.
5. Volte ao Safari e toque em Continuar. Tem que entrar no painel pareado e mostrar "iPhone conectado" com os passos da Tela de Início.
6. Feche o Safari e abra de novo `https://<nome-do-mac>.local:4777`. Agora tem que abrir sem aviso de site inseguro.
7. Compartilhar > Adicionar à Tela de Início > Adicionar. Abra pelo ícone. Tem que abrir em tela cheia, sem barra do Safari.
   Se o ícone mostrar "Deck não pareado", toque em Digitar o código do Mac e digite os 6 dígitos de Conectar iPhone
   (anote aqui se o iPhone copiou ou não o código do Safari para o ícone, é o ponto que não deu para provar daqui).
8. Deite o iPhone e espere mais que o bloqueio automático dele. A tela tem que ficar acesa. Saia do app e volte: continua acesa.
9. Toque numa tecla que só abra um app (por exemplo Notas) e veja o Mac abrir.
10. Desligue o Mac (ou saia do Deck) e abra o ícone do iPhone: tem que abrir na hora e mostrar "Mac desconectado". Ligue o Mac e confira que reconecta sozinho.

| Ponto | Resultado |
|---|---|
| Safari avisa de certificado e deixa visitar o site | pendente |
| Passo a passo do certificado aparece e o `/ca.crt` baixa como perfil | pendente |
| Perfil instalado e confiado | pendente |
| Continuar pareia e entra no painel | pendente |
| Abre em HTTPS sem aviso pelo nome `.local` | pendente |
| Adiciona à Tela de Início com o ícone do Deck | pendente |
| Abre em tela cheia, deitado e em pé | pendente |
| O ícone abre pareado ou pede o código (qual dos dois) | pendente |
| Wake Lock aceito e tela acesa além do bloqueio automático | pendente |
| Volta acesa depois de sair e voltar para o app | pendente |
| Tecla executada no Mac | pendente |
| Com o Mac desligado o ícone abre na hora e mostra "Mac desconectado" | pendente |
| Mac volta e o painel reconecta sozinho | pendente |
