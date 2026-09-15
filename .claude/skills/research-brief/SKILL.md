---
name: research-brief
description: >
  Turn a question about current ecosystem state (tool versions, EOL,
  deprecations, authoritative docs) into either a researcher-agent task
  (if web access is available) or a ready-to-paste Perplexity/ChatGPT
  prompt plus instructions for filing the answer back into this repo. Use
  whenever a claim needs checking against current upstream reality rather
  than training-data memory.
---

# research-brief

## Steps

1. State the precise question — "what is the current stable OpenTofu
   version" is answerable; "tell me about OpenTofu" is not a research
   task, it's a doc read.
2. If this session has working web access, delegate to the `researcher`
   agent directly with that precise question.
3. If not (or the user prefers), produce a Perplexity/ChatGPT-ready prompt:
   the question plus the minimal context block from
   `docs/contributing/ai-collaboration.md`, and ask for citations.
4. State explicitly where the answer should land once obtained: a
   `mise.toml` version bump, a `docs/architecture/*.md` update, or a new
   ADR if it changes a prior decision — per
   `docs/contributing/ai-collaboration.md`'s rule that research isn't
   real until it's in Git.

## Output

Either the researcher agent's cited brief, or the ready-to-paste external
prompt plus the filing instruction from step 4. Never present unverified
version/deprecation claims as fact — flag them as needing this process if
skipped.
