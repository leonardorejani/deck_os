# Avisos de fora e GitHub (19/11/2026)

Camadas tocadas: SPEC, núcleo (mac/Nucleo), app do Mac (mac/App), painel (painel/) e ponte do iPhone (ios/Web).

- Núcleo: `AvisosDeFora.swift` (armazém com limites, roteador da porta de fora e chave), `ServidorDeFora.swift` (HTTP só em 127.0.0.1), `Fontes/GitHub.swift` (leitura pelo gh e abrir no Mac), campos novos no `Estado` e rota `POST /api/github/abrir`.
- App do Mac: Este Mac ganhou "Avisos de fora" (chave, Copiar, exemplo de curl, Trocar) e o editor de tecla ganhou as teclas de fábrica GitHub e Valores.
- Painel: `externos.js` (toast, folha Valores, folha GitHub), teclas de fábrica no editor do iPhone e `abrirGitHub` no canal e na ponte (paridade conferida por `ios/scripts/testar-ponte.js`).

Decisões:

- A porta de fora é HTTP simples em 127.0.0.1, com chave própria em arquivo 0600, para o curl de um script não depender de certificado nem do código do iPhone. O pedido gasta uma vaga de taxa antes de a chave ser conferida, para chute de chave também ser limitado.
- GitHub vira tecla de fábrica (como Controles e Meet), não bloco novo: o Mac só chama o gh quando o perfil ativo tem a tecla, e só quando o iPhone pede o estado, com cache de 3 minutos.
- O endereço do PR nunca vai para o iPhone. O iPhone manda o id e o Mac só abre o que acabou de ler, e só endereço https do github.com.
