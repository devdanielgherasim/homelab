---
name: write-runbook
description: >
  Write a new operational runbook under docs/runbooks/ in this
  repository's standard shape (preconditions, steps, verification,
  rollback, downtime). Use only after a procedure has actually been
  performed at least once — not for a speculative "how this should
  probably work" writeup.
---

# write-runbook

## Precondition

The procedure being documented must have actually been run — this skill
is for capturing real operational knowledge, not designing a procedure
from scratch. If the procedure hasn't been performed yet, that work
belongs in `docs/architecture/` (design) or `docs/troubleshooting/`
(diagnosis), not a runbook.

## Steps

1. Create `docs/runbooks/<kebab-case-name>.md`.
2. Follow the fixed shape (see `docs/runbooks/README.md`):
   - **Preconditions** — exact state required before starting.
   - **Steps** — the exact procedure, as commands where possible, not
     paraphrased.
   - **Verification** — the specific command/output/dashboard that
     confirms success. "It worked" is not verification; the check is.
   - **Rollback** — how to undo it, concretely.
   - **Expected downtime** — state it, even if "none."
3. If the runbook covers a destructive or infrastructure-changing
   procedure, cross-reference `AGENTS.md`'s destructive-action policy —
   the runbook documents *how*, the policy still governs *whether/when*.
4. Link it from `docs/runbooks/README.md` if not already listed there.

## Output

The runbook's path. State plainly whether every step in it was actually
verified when written, or whether some step is inferred/untested — per
`AGENTS.md`'s claim vocabulary.
