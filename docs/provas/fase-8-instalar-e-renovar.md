# Prova da fase 8: instalar e renovar

Itens 1 a 3 da fase 8 do `PLANO.md`: `build.sh`, `instalar-iphone.sh` e a renovação automática no `Deck.app`.

## O que foi feito e provado (10/11/2026, Xcode 26.6, macOS 26.5)

- `./build.sh`: 1m32 do zero. `dist/Deck-1.0.dmg` (9 MB) monta, mostra `Deck.app` e o atalho `Aplicativos`, e o app
  dentro diz versão 1.0, compilação 13, assinatura local (`Signature=adhoc`).
- Instalação em `/Applications` pelo `.dmg` e abertura com `open -g --args --renovar-agora`, sem janela.
- Renovação real pelo próprio `Deck.app`, com o iPhone de teste no cabo e desbloqueado, 10 segundos:

```
2026-11-11T01:59:35Z renovacao: iniciada (pedido na tela)
2026-11-11T01:59:45Z renovacao: ok. Instalado em 2026-11-11T01:59:45Z. O perfil novo vence em 2026-11-18T01:59:42Z
```

## O achado: o Xcode reaproveita o perfil

Na primeira rodada o app reinstalou, mas o vencimento do perfil não andou:

```
2026-11-11T01:57:22Z renovacao: ok. ... O perfil novo vence em 2026-11-17T21:17:32Z   (perfil criado em 10/11 18:17)
```

O `xcodebuild -allowProvisioningUpdates` usa o perfil em cache (`~/Library/Developer/Xcode/UserData/Provisioning Profiles`)
enquanto ele vale. As três renovações da prova 0.4 só provaram que a instalação roda sem toque, não que o prazo anda.
Agora o renovador apaga o perfil do app do iPhone antes de compilar (só ele, o do app de prova fica) e o Xcode gera outro:
vencimento foi de 17/11 21:17 para 18/11 01:59 (7 dias a partir da hora da renovação).

## Motivos e agenda

Cobertos por teste com executor e relógio falsos (`mac/Testes/RenovacaoTestes.swift`, `mac/App/Testes/RenovacaoAgendaTestes.swift`):
iPhone fora do cabo, bloqueado, sessão da Apple ID vencida, Xcode ausente, projeto não encontrado, xcodegen ausente e
erro de compilação. Não foram provados com o aparelho de verdade (não dá para provocar sem atrapalhar o uso dele).

## Renovação silenciosa e pelo Wi-Fi (11/11/2026, só leitura)

Auditoria: a renovação chama só `xcrun` (`--find` e `devicectl`), `bash`, `xcodegen`, `xcodebuild` e `security`, todos de
linha de comando, e o app é `LSUIElement`. Nada de `open`, `osascript`, Xcode ou Finder (teste
`testRenovarSoUsaFerramentasDeLinhaDeComandoNuncaAbreAppNemTela`).

Prova real, sem reinstalar (`DECK_PROVA_REAL=1 swift test --package-path mac --filter RenovacaoRealTestes`):

```
iphone: achado, caminho: Wi-Fi, situacao: liberado (2740 ms)
ultima instalacao: 2026-11-11T10:32:31Z, proxima renovacao: 2026-11-16T10:32:31Z, devida agora: false
```

O iPhone Exemplo estava sem cabo (`transportType: localNetwork`, estado "available (paired)") e o Deck o achou e leu o
bloqueio. O app em primeiro plano (`lsappinfo front`) e a contagem de apps registrados (70) não mudaram antes e depois.

Ficou sem prova no aparelho: instalar de verdade pelo Wi-Fi (a mesma sequência provada no cabo, só muda o caminho que o
`devicectl` escolhe) e o que acontece com o app do iPhone se ele estiver aberto na hora da instalação.

## Falta

- Primeira renovação por agenda (a partir do dia 5 depois da instalação). O caminho é o mesmo do `--renovar-agora`.
- Teste de ponta a ponta do zero feito por ele, com o `.dmg`, o PWA e o app nativo.
- `instalar-iphone.sh` não foi rodado de ponta a ponta (o iPhone já tem o app): só a sintaxe e o `ios/instalar.sh` que ele chama.
