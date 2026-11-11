# L-XXX — A lista de acessos dependia de marcas que ninguém gravava

**Date:** 2026-11-11
**PR:** fix/mac-acessos-do-mac
**Affected layers:** spec, prototipo, mac (app)
**Severity:** medium

## Symptom (P1)

Palavras do Leonardo: "As permissões não aparecem no painel, o app pede para calendários entre outros."

## Cause

A seção Acessos do Mac só listava o que estava recusado, e a detecção de recusa nunca disparava:
Acessibilidade e Acesso Total ao Disco dependiam das chaves `acessoPedido.*` e `acessoRecusado.*`, que nenhum código
gravava. Calendários só contava recusa explícita (nunca "não perguntado"), a Automação só olhava o Spotify, e Bluetooth e
Rede Local não existiam. Sem recusa, a seção sumia do menu lateral e o macOS perguntava de surpresa. Um Mac sem nenhum
acesso liberado mostrava `recusados() == []` (leitura real: Calendários e Bluetooth no estado 0, nunca perguntado).

## Fix

A seção lista todos os acessos com o estado lido (Liberado, Não perguntado, Recusado, Sem como conferir), e o "Permitir"
faz o próprio Deck pedir e gravar a marca. Testes com detectores falsos em `ConectarMacTestes.swift` (`AcessosTestes`).

## Rule

Lógica que depende de uma marca gravada por outro código precisa de teste que prove quem grava a marca. Estado de
permissão se lê do sistema, não se deduz de uma lista de recusas.
