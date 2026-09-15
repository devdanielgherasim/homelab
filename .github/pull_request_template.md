## What

<!-- What does this change, and why. -->

## Type

- [ ] feat
- [ ] fix
- [ ] docs
- [ ] refactor
- [ ] test
- [ ] chore
- [ ] security

## Checklist

- [ ] `make validate` passes locally (or CI is green)
- [ ] `make security` / gitleaks shows no new findings
- [ ] No real secrets, credentials, or real home-network identifiers committed — see [`docs/security/public-repository.md`](../docs/security/public-repository.md)
- [ ] Docs updated if this changes architecture or behavior (`docs/architecture/*`, an ADR, or `STATUS.md`)
- [ ] Claims in this description use [`AGENTS.md`](../AGENTS.md)'s vocabulary ("statically validated" vs. "tested" vs. "deployed" vs. "verified") accurately

## Does this touch infrastructure?

- [ ] No — docs/config/CI only
- [ ] Yes — describe impact, rollback, and expected downtime per [`AGENTS.md`](../AGENTS.md)'s destructive-action policy, and confirm this has **not** been applied to real infrastructure by this PR alone (applies require explicit separate approval)
