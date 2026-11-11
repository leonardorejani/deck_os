# L-XXX — Reinstalar não renova se o Xcode reaproveita o perfil

**Date:** 2026-11-10
**PR:** fase 8 (instalar e renovar)
**Affected layers:** mac (renovador), ios (instalação), spec
**Severity:** high

## Symptom (P1)

A renovação "deu certo" (`App installed`) mas o log do Deck mostrou o mesmo vencimento do perfil de antes.

## Cause

O `xcodebuild -allowProvisioningUpdates` reaproveita o perfil guardado em `~/Library/Developer/Xcode/UserData/Provisioning Profiles`
enquanto ele vale. O app reinstalado carrega o perfil velho e vence junto com ele. A prova 0.4 só conferiu que a instalação roda.

## Fix

O renovador apaga o perfil do app do iPhone antes de compilar. Teste: `testApagarPerfisMexeSoNosDoAppDoIphone` e
`testApagaOPerfilVelhoAntesDeCompilarParaOVencimentoAndar`.

## Rule

Prova de renovação confere a data de vencimento do perfil, não só "App installed".
