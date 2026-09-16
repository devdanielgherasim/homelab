# AI CLI Orchestrator — Design Spec

Status: Approved (brainstorming complete 2026-09-16)
Scope: **Global** — `~/.claude/` additions, not specific to this repository.
This spec and its implementation plan live in this repo's `docs/`/`plans/`
only because neither `~/.claude/` nor `~/.ai/` is a git repository (verified
2026-09-16); the feature itself is not homelab-specific.

## Why

Claude Code's own context/token budget is one of three independent-cap
tools the user has (Claude Code, Codex CLI, Perplexity Pro), per
`~/.ai/routing.md`. Two more capable CLIs are already installed and
**free** (Gemini CLI, GitHub Copilot CLI) and are not yet part of that
routing convention at all. Goal: let Claude Code delegate real work to
Gemini/Copilot (free) and Codex (paid but a separate, already-owned
cap) so Claude's own tokens are spent on orchestration, synthesis, and
judgment — not on work another already-available tool can do.

## Real inventory (verified live 2026-09-16, not assumed)

| Backend | Binary | Non-interactive invocation | Notes |
|---|---|---|---|
| Codex CLI | `codex` (codex-cli 0.154.0) | `codex exec [PROMPT] --json -o <file>` | Already paid for; existing routing.md role (second opinion / parallel track) unchanged. |
| Gemini CLI | `@google/gemini-cli@0.60.0`, on PATH as `gemini` | `gemini -p "<prompt>"` | The `gemini` shell shim errors under Git Bash specifically (`This: command not found`) — the package itself is intact; invoke via `node <npm-global>/node_modules/@google/gemini-cli/bundle/gemini.js` to sidestep the shim entirely, or accept the shim under PowerShell/cmd (not yet verified there — check at implementation time). |
| GitHub Copilot CLI | `copilot` (GitHub Copilot CLI 1.0.85), installed via WinGet, already on PATH | `copilot -p "<prompt>" -s` | **Correction during brainstorming**: initially assumed this required `gh copilot`'s own download (it doesn't — `gh copilot` would have detected and used this same existing binary). No install/download step needed at all. |
| Perplexity | — (web-app only) | N/A — hand-off only | Confirmed in `routing.md` AD-4: no API, by design. Unchanged. |

Node v25.2.1 / npm 11.1.0 and Python 3.14.7 both present on Windows;
**Node chosen** for the MCP server (see Decisions).

## Decisions

- **Language: Node**, using `@modelcontextprotocol/sdk` (official, stdio
  transport). Reasoning: Node already used in this environment (this
  repo's own `.claude/hooks/*.mjs`), zero additional setup (no venv
  story exists anywhere else in this user's toolchain), first-party SDK.
- **Call model: synchronous, per-call timeout, no async job queue.**
  Claude Code can already issue multiple independent MCP tool calls in
  parallel within one turn — that's where cross-backend concurrency
  comes from, not a custom job-queue/poll-status mechanism. Simpler,
  avoids inventing state (job storage, cleanup of stale jobs).
- **One tool per backend, not split by sub-capability.** `ask_copilot`
  is a single tool (not `explain`/`suggest` split) because the real
  installed `copilot` CLI is a general agentic assistant, not the old
  narrow `gh copilot suggest`/`explain` preview pair the request
  initially assumed.
- **Backend division of labor** (user: "use them as efficiently/
  professionally as possible" — delegated to Claude's judgment,
  grounded in each product's actual positioning, not invented):
  - **Codex** — second opinion / independent parallel track / security
    review (unchanged from `routing.md`'s existing table).
  - **Gemini** — general reasoning, broad explanations, analysis not
    requiring live web.
  - **Copilot** — concrete code edits/fixes, git/repo-aware suggestions
    (GitHub Copilot lineage).
  - **Perplexity** — live web only, hand-off draft, never auto-sent
    (unchanged).
  - **Claude itself** — orchestration decisions, cross-backend
    synthesis, anything that depends on this session's own
    already-loaded context (files read, decisions made earlier in the
    conversation) enough that re-explaining to a cold delegate would
    cost more than it saves.
- **Delegation posture: strong default bias, not hard-forced.** Flagged
  and confirmed with the user: `~/.ai/memory/decisions.md` AD-5
  ("nothing here is automated or auto-dispatched") stays true in letter
  — Claude still decides per-turn whether to delegate — but the
  orchestrator skill's instructions bias hard toward delegating first.
  This *is* an evolution of AD-5's spirit; documented as a new decision
  entry (exact number determined at implementation time by reading the
  current `decisions.md`), not a silent reinterpretation.
- **No disk logging in the MCP server.** stdout/stderr/exit-code return
  directly in the MCP tool response; nothing written to a log file.
  Satisfies "never log secrets from CLI output" structurally (nowhere
  for a secret to land) rather than via redaction logic that could miss
  a pattern.
- **Errors are never swallowed.** Timeout → `{timedOut: true, exitCode:
  null, stdout, stderr}` (SIGTERM, then SIGKILL after a grace period).
  Non-zero exit → exit code + stderr (truncated ~4000 chars to bound
  context cost) returned as a failure, never coerced into a success shape.
- **`draft_perplexity_handoff` makes no network/process call at all** —
  pure local string formatting. Structurally incapable of auto-sending
  anything, not just policy-restricted from it.

## Architecture

```
~/.claude/
├── mcp-servers/ai-cli-orchestrator/
│   ├── package.json
│   ├── index.mjs                       # MCP stdio server entry point
│   ├── src/lib/run-cli.mjs             # spawn + timeout + capture (shared)
│   ├── src/tools/ask-codex.mjs
│   ├── src/tools/ask-gemini.mjs
│   ├── src/tools/ask-copilot.mjs
│   ├── src/tools/draft-perplexity-handoff.mjs
│   └── README.md
└── skills/
    ├── ask-codex/SKILL.md
    ├── ask-gemini/SKILL.md
    ├── ask-copilot/SKILL.md
    ├── perplexity-handoff/SKILL.md
    └── ai-orchestrator/SKILL.md         # top-level delegation policy
```

Registration: `claude mcp add ai-cli-orchestrator -s user -- node
~/.claude/mcp-servers/ai-cli-orchestrator/index.mjs` (user scope — global,
not tied to any one project's `.mcp.json`).

## Tool signatures

- `ask_codex(prompt, cwd?, timeout_sec? = 120)`
- `ask_gemini(prompt, context_files?, cwd?, timeout_sec? = 120)`
- `ask_copilot(prompt, cwd?, timeout_sec? = 120)`
- `draft_perplexity_handoff(question, context)` — returns a formatted
  prompt + a note ("paste this into Perplexity"); never calls anything,
  no timeout applicable.

Default 120s for all three CLI-backed tools, overridable per call for a
task known to need longer (e.g. a heavier Codex reasoning pass) —
matches the number discussed and agreed during brainstorming.

## Orchestrator skill algorithm

1. For a new delegable task (implementation/research/explanation/edit),
   ask: does this depend heavily on this session's own context (files
   already read, decisions already made here) such that re-explaining
   it to a cold delegate would cost more than delegating saves?
   - No → delegate: Copilot (concrete code edit), Gemini (reasoning/
     explanation), Codex (second opinion/parallel track), or a
     Perplexity hand-off draft (live web).
   - Yes → do it directly in Claude.
2. Never delegated: final synthesis across backends; anything touching
   a destructive-action policy (a delegate's prompt is scoped safely,
   never a blind forward of a dangerous request); anything requiring a
   project-local skill/hook a delegate CLI can't read.
3. When multiple backends answer the same question, synthesize
   (agreement/disagreement + Claude's own judgment) — never concatenate
   raw outputs unfiltered.

## Skills content plan

Each per-backend skill: short, cites `~/.ai/routing.md`'s table instead
of duplicating it, states the one MCP tool to call, and any
backend-specific gotcha found during inventory (e.g. Gemini's shim
issue). The `ai-orchestrator` skill holds the algorithm above and links
to the four backend skills.

## `~/.ai/routing.md` update

Add two rows to the existing Decision table (free general reasoning →
Gemini; free concrete code edit → Copilot) and a short section pointing
at the new MCP tools/skills, so Codex CLI (which also reads this file)
knows they exist even though it can't call them the same way.

## Explicitly out of scope

- Auto-installing `gh copilot`'s own downloaded binary — moot; the
  already-installed WinGet `copilot` is used directly.
- Any auto-post/auto-send behavior anywhere (no auto-paste to
  Perplexity, no auto-PR, no auto-commit) — hard constraint from the
  user, holds for every tool without exception.
- Touching this repository's own `.claude/` configuration — this is
  `~/.claude/` global scope only.
