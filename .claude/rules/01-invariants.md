# Deck Invariants

Rules that can **never** be violated. If a change breaks any invariant, it is rejected, no exceptions.

## About the product

1. **O Mac configura, o iPhone mostra.** Toda configuração mora no `config.json` do Mac. O iPhone só grava pelo modo organizar, pela API, no mesmo arquivo. Nunca existe config só no iPhone.
2. **Nada sai da rede de casa.** Sem servidor externo, sem site público. A API só responde com o código de acesso do pareamento.
3. **Dado de outro app é só leitura.** O banco do WhatsApp, a agenda e os jobs do Claude Code são lidos, nunca escritos. Única exceção (decisão de 12/11/2026, SPEC seção 13): "Novo compromisso" da agenda cria um evento no Calendário ou um lembrete no app Lembretes, só pela rota autenticada `POST /api/agenda/criar`, só o que a pessoa pediu. Nunca altera nem apaga o que já existe.

## About sensitive data

4. **Secrets never in code.** Tokens, API keys, passwords only in `.env` (gitignored) or a secrets service.
5. **PII in logs = forbidden.** Tax IDs, phone numbers, emails only obfuscated.
6. **DB queries always parameterized.** String concatenation with user input = SQL injection.

## About commits

7. **Commits without explicit authorization = forbidden.** A vague reply ("ok", "nice") is not authorization. Only "commit it" / "make a commit" / "go ahead and commit".
8. **`--no-verify` forbidden.** A failing hook = diagnose it, don't skip it.
9. **Mentioning AI/Claude in a commit or code = forbidden.** Author is always human.

## About user-facing content

10. **Correct accentuation in the UI language.** Match the locale's conventions; never plain ASCII in content humans read.
11. **No technical jargon in the UI.** Blocklist adapted to the domain.

## About critical pipelines

12. **Toda ação de tecla roda no Mac**, por `/api/botao/<id>` com o código de acesso. O iPhone nunca executa nada sozinho, e acesso do macOS é pedido na hora do uso, nunca em lista de cara.

---

**Cataloging:** if a new bug violated an invariant and the invariant was already here, the bug is the problem. If the invariant didn't exist, **catalog it immediately** after the fix is merged.
