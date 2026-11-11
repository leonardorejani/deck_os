# Contribuindo com o Deck

Obrigado por querer ajudar. O Deck é código aberto, com licença [MIT](../LICENSE).

## Antes de começar

- Leia o [`README.md`](../README.md) e o [`SPEC.md`](../SPEC.md): o SPEC é a fonte do que o produto faz e do que já foi decidido.
- Mudança grande, abra uma [issue](https://github.com/leonardorejani/deck_os/issues/new/choose) antes e conte a ideia. Evita trabalho jogado fora.
- Achou um erro? Abra a issue com o passo a passo para reproduzir.

## Como rodar os testes

```bash
node painel/teste/rodar.mjs        # painel contra o Mac de mentira (precisa do Chrome)
swift test --package-path mac      # núcleo do Mac
swift test --package-path ios/Pacote
.claude/verificar.sh               # o critério de pronto do projeto
```

O app do Mac e o do iPhone só compilam no macOS com Xcode e `xcodegen`. Veja o `README.md` para instalar.

## Fluxo de PR

1. Faça um fork e crie uma branch a partir da `main`.
2. Uma mudança lógica por PR, com teste. Bug corrigido ganha um teste que falha antes e passa depois.
3. Commits no padrão Conventional Commits, em português: `feat:`, `fix:`, `docs:`, `chore:`.
4. Abra o PR contra a `main` e preencha o modelo. Mostre o que mudou e como testar.
5. O CI precisa ficar verde. Quem mantém revisa e faz o merge.

Texto de interface e documentação em português do Brasil, sem emoji.

## O que o CI faz com PR de fork

PR de fork só roda depois que o dono aprova a execução (botão "Approve and run" no PR). Depois de aprovado, roda no
runner do GitHub (`ubuntu-latest`), sem acesso a segredos. Se o CI não começa no seu PR, é essa aprovação que falta.
Push na `main` e PR de branch do próprio repositório usam o runner próprio do dono (rótulo `leve`). Os fluxos que
usam segredo só rodam nesse segundo caso.

O núcleo Swift roda dentro da imagem `swift:6.2` do Docker, que existe nos dois runners, então o resultado é o mesmo.

## Para quem mantém: ajustes do repositório público

Esses itens ficam nas configurações do GitHub e não dá para versionar. Conferir ao abrir ou reabrir o repositório:

1. Settings > Actions > General > Fork pull request workflows: marcar "Require approval for all outside collaborators".
2. Runner próprio: o runner self-hosted só recebe push na `main` e PR de branch do próprio repositório (escolha feita em
   cada `runs-on`). Para desligar de vez, criar a variável de repositório `RUNNER_LEVE` com o valor `["ubuntu-latest"]`.
3. Settings > Actions > General > Workflow permissions: "Read repository contents" como padrão. Os fluxos pedem o que precisam.
4. Branch `main` protegida: PR obrigatório e o CI verde como condição de merge.
5. `@claude` em comentário só funciona para dono, membro e colaborador (`claude-mention.yml`). Conferir que o segredo
   `CLAUDE_CODE_OAUTH_TOKEN` é de uma conta que aceita esse uso.
