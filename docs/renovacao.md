# Renovação automática do app no iPhone

Em linguagem simples: como o Deck mantém o app nativo vivo no iPhone sem você fazer nada, e o que precisa estar de pé para isso funcionar.

## Por que existe

O app nativo é instalado com a conta grátis da Apple, e a Apple faz esse tipo de app parar de abrir depois de 7 dias. O Deck do Mac instala o app de novo antes disso, e o prazo volta a contar do zero. Você não abre tela nenhuma.

## Como funciona

1. **Quando.** A cada 5 dias, contados da última instalação boa. Isso deixa 2 dias de folga antes do app vencer.
2. **Em silêncio.** O Deck roda tudo em segundo plano, com só o ícone na barra de menus. Nada abre janela e nada traz outro app para a frente: ele usa só comandos de terminal (compilar e instalar), nunca abre o Xcode nem o Finder.
3. **Passos.** Confere se o Xcode está pronto, procura o iPhone, empacota a página do painel, gera o projeto, apaga o perfil velho do app (é isso que faz o prazo andar de verdade), compila e instala no iPhone. No fim lê o vencimento do perfil novo e guarda a data.
4. **Cabo ou Wi-Fi.** Vale o iPhone no cabo ou no mesmo Wi-Fi do Mac, desde que o Xcode enxergue o aparelho pela rede (em Xcode > Window > Devices and Simulators ele aparece com o ícone de rede). Se houver iPad, relógio ou outro aparelho ao alcance, o Deck ignora e usa só o iPhone.
5. **Se não der.** O motivo fica guardado em português, e o Deck olha o iPhone a cada 5 minutos (uma consulta curta, sem compilar). Quando o iPhone aparece ou é desbloqueado, tenta de novo. Quando o problema não é o iPhone (conta da Apple, Xcode, compilação), só repete depois de 1 hora, para não compilar à toa.
6. **Quando avisa.** Só quando o prazo aperta: 12 horas depois da hora de renovar sem ter dado certo. Aí aparecem o cartão amarelo em Ajustes > Conexões, uma linha no menu da barra e o selo "1" na barra lateral. Renovou sozinho, ou falhou com folga: nenhum aviso.

## Condições para renovar sozinho

- O Mac está ligado e o Deck está aberto na barra de menus (acordado: Mac dormindo não renova, e ele tenta quando acordar).
- O iPhone está ao alcance: no cabo, ou no mesmo Wi-Fi com o iPhone pareado com o Xcode pela rede.
- O iPhone pode estar bloqueado, menos logo depois de ligar ou reiniciar: nesse caso ele precisa ser desbloqueado uma vez.
- O Xcode está instalado e a conta da Apple está entrada nele (Xcode > Settings > Apple Accounts). Se a sessão vencer, o Deck avisa o motivo e espera você entrar de novo.
- O Deck sabe onde está a pasta do projeto no Mac, porque renovar é compilar de novo. O `build.sh` e o `instalar-iphone.sh` gravam isso em `~/Library/Application Support/Deck/renovacao.plist`.
- O `xcodegen` está instalado (`brew install xcodegen`).

## Como ver o que está acontecendo

- Em Ajustes > Conexões, grupo do app nativo: a linha "Renovação automática" mostra a próxima data (ou "Tenta de novo sozinha"), e embaixo uma explicação curta destas condições. "Renovar agora" é a ação manual.
- O histórico fica em `~/Library/Logs/Deck/deck.log`, linhas que começam com `renovacao:`. Ali aparece também por onde o iPhone foi achado ("pelo Wi-Fi" ou "pelo cabo").

## O que o Deck nunca faz

- Abrir janela, abrir o Xcode, trazer app para a frente ou pedir tela de confirmação.
- Mexer em outro aparelho que não seja o iPhone.
- Escrever fora do próprio perfil do app do iPhone e das pastas de build do projeto.

Prova de cada parte: `docs/provas/fase-8-instalar-e-renovar.md`.
