---
name: create-adr
description: >
  Create a new Architecture Decision Record using this repository's
  template and numbering, and add it to the ADR index. Use only for a
  meaningful architectural decision (a real fork in the road with
  alternatives), not for routine implementation details — see the
  criteria below before creating one.
---

# create-adr

## When an ADR is warranted

Ask: did this decision have real alternatives that were seriously
considered, and would a future engineer reasonably ask "why this and not
that"? If yes, it's ADR-worthy. Examples: choosing a CNI, choosing a
GitOps tool, choosing how remote access works. Non-examples: a specific
variable name, a directory layout tweak, a lint rule setting — these go in
a normal doc or commit message, not an ADR.

## Steps

1. Find the next number: check `docs/adr/README.md`'s index (or list
   `docs/adr/NNNN-*.md` and take the highest + 1).
2. Copy `docs/adr/template.md` to `docs/adr/NNNN-kebab-case-title.md`.
3. Fill in Context, Decision, Alternatives considered (at least one real
   alternative with its rejection reason), Consequences (trade-offs
   accepted, not just benefits).
4. Set status:
   - **Proposed** by default — unless the user has explicitly confirmed
     the decision is final in this conversation.
   - Never mark **Accepted** on your own judgment for a significant
     architectural choice; that's the project owner's call.
5. Add a row to the table in `docs/adr/README.md`.
6. If this ADR changes or replaces an earlier one, update the earlier
   ADR's status to "Superseded by [NNNN](NNNN-title.md)" and link both
   directions.

## Output

The new ADR's path and status. If you defaulted to "Proposed," say that
explicitly and that it needs confirmation to become "Accepted."
