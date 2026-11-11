# Safe Merge — double gate + `mergeStateStatus: CLEAN`

Operational invariant of Deck. Loaded in every session that runs
`gh pr merge`. Origin: a recurring incident where an agent merged a PR with a
failing check because it trusted `mergeable` without checking `mergeStateStatus`.
Classified as serious.

## Founding principle

**Merge a PR ONLY when `mergeStateStatus === "CLEAN"`.** `mergeable ===
"MERGEABLE"` alone is INSUFFICIENT — they report different concepts.

| Field | Meaning | Sufficient? |
|---|---|---|
| `mergeable: MERGEABLE` | No file conflict | ❌ NO |
| `mergeStateStatus: CLEAN` | All checks passed, zero visible failure | ✅ YES |
| `UNSTABLE` | Mergeable but a check is visibly failing | ❌ |
| `BLOCKED` | Branch protection / missing approval | ❌ |
| `BEHIND` | Rebase needed | ❌ |
| `DIRTY` | Active conflict | ❌ |

## Mandatory canonical wrapper

Every Claude Code session OR manual terminal uses
`scripts/gh-pr-merge-safe.sh` instead of `gh pr merge` directly.

```bash
bash scripts/gh-pr-merge-safe.sh 42 --squash --delete-branch
```

The wrapper: queries `mergeStateStatus`. If != CLEAN → lists `gh pr checks`
+ exit 1. If == CLEAN → merges. `gh pr merge` directly = violation.

Bypass: `DECK_MERGE_UNSAFE=1` only with the owner's explicit
sign-off documented in the commit/PR body and a context where the non-CLEAN
state is provably OK.

## Double gate (who decides the merge)

### Gate 1 — executor (local Claude Code session)

Investigates, implements, opens the PR. Local smoke green before the push.

### Gate 2 — reviewer (Claude AI review in the GitHub Action)

Posts an informational verdict: status + layers + findings + caveats +
recommendation. **Branch protection does not block the merge — the verdict is
input, not authorization.**

### Final decision by tier

| Tier | Content | Who triggers the merge |
|---|---|---|
| **S inert** | `docs/**`, `build-log.md`, `.planning/workstreams/**`, `.project-structure.md`, `.todos-report.md` | `pr-auto-merge.yml` autonomous (nothing deploys, no invariant is reached) |
| **H** | everything else: code, CI, rules, root configs, speech, money | **The executor merges by itself** with `gh-pr-merge-safe.sh` once the PR is CLEAN, `.claude/verificar.sh` is green and the adversarial verification found nothing open |

Tier H pattern (decisão do Leonardo, 10/11/2026: "nao tenho que liberar PR. tu tem que usar o
keepwright pra automatizar tudo e nao deixar sair do trilho"): executor implementa, um verificador
tenta quebrar, o que ele reproduz é corrigido com teste, o CI fica verde, o wrapper confirma CLEAN e
o próprio executor mergeia. Ninguém espera o ok dele. O trilho é o gate, não a pessoa.

`go`/`ok` confirms the merge of that already-prepared PR. It is not permanent
authorization and does not cover commits.

## Anti-pattern

❌ `gh pr merge` without checking `mergeStateStatus`
❌ `gh pr merge` directly without the wrapper
❌ AI→AI loop merging Tier H without a human go
❌ Tier S auto-merge when 1 file in the diff falls outside the allowlist
❌ Bypass `DECK_MERGE_UNSAFE=1` without documented sign-off
