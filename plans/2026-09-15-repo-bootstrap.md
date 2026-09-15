# 2026-09-15 — Repository bootstrap

Goal: bootstrap the homelab repository's engineering environment and
AI-agent operating environment (no infrastructure provisioning). Full
design was presented and approved in-session before implementation.

## Tasks

- [x] Safety floor: `.gitignore`, `.gitattributes`, `.editorconfig`, `.gitleaks.toml`, `LICENSE`, `SECURITY.md`
- [x] Authority layer: `AGENTS.md`, `CLAUDE.md`, `STATUS.md`, `docs/README.md`
- [x] Architecture docs ported from `docs/homelab-architecture.docx`, sanitized (real router model/LAN removed), Mermaid diagrams: `overview.md`, `networking.md`, `infrastructure.md`, `kubernetes.md`, `gitops.md`, `observability.md`
- [x] Security docs: `public-repository.md`, `self-hosted-runners.md`, `threat-model.md`, `secrets.md`
- [x] Proxmox responsibility model + manual-install doc: `docs/proxmox/installation.md`
- [x] ADR system: `docs/adr/README.md`, `template.md`, 8 draft ADRs (all status: Proposed)
- [x] Runbooks/troubleshooting/contributing scaffolding (content-light, by design — no fabricated procedures)
- [x] Developer interface: `Makefile`, `mise.toml`, `scripts/doctor.sh`, lint configs, `.pre-commit-config.yaml`
- [x] Claude environment: `.claude/settings.json` (3 hooks), 4 agents, 5 skills, 2 commands
- [x] CI: `validate.yml`, `security.yml` (GitHub-hosted only, path-filtered, `contents: read`), issue templates, PR template, CODEOWNERS, dependabot
- [x] Domain READMEs: `tofu/`, `ansible/`, `kubernetes/`, `scripts/`
- [x] Root `README.md`
- [x] `.env.example` / example config files — deliberately **not** created yet: no `tofu`/`ansible` module exists for one to accompany, so a standalone example file would be misleading. Revisit when the first real module/playbook lands.
- [x] Run all safe local validation; report pass/fail/unavailable
- [x] Final report to user: tree, component explanation, manual-setup items, next milestone

## Validation results (2026-09-15)

- `gitleaks detect` (whole working tree): **no leaks found**.
- 7/7 YAML files parse clean (PyYAML).
- `.gitleaks.toml` valid TOML; `.markdownlint.jsonc` valid JSONC.
- 3/3 `.claude/hooks/*.mjs` pass `node --check`; all three exercised
  live against fixture input — `guard-command.mjs` correctly blocked a
  `tofu apply` pattern and allowed `git status`; `post-edit.mjs` ran
  clean against a test file; `session-brief.mjs` printed correctly. The
  harness's own PreToolUse hook also fired against this session's real
  tool calls mid-bootstrap, confirming the hook is live, not just
  syntactically valid.
- Makefile: 100% tab-indented recipes; `make help`/`make validate`/
  `make security`/`doctor.sh` all executed successfully in WSL2 Ubuntu
  (real execution, not just review) and degraded gracefully with 15/16
  tools absent.
- 142 relative Markdown links checked; 140 resolve, 2 flagged were false
  positives (literal `NNNN-title.md` placeholder text in the ADR
  template/skill, not real links).
- `.claude/settings.json` valid JSON.
- Could not run locally (tool not installed / needs a real target):
  `tofu fmt`/`validate` (no `.tf` files exist yet), `ansible-lint` (no
  playbooks yet), `kubeconform`/`yamllint`/`shellcheck` binaries (not on
  PATH in this environment — logic path exercised via the equivalent
  PyYAML/`node --check` checks above instead), GitHub Actions workflow
  execution (requires a push/PR on GitHub).

## Deliberate deviations from initial verbal design

- GitHub Actions third-party actions pinned to version tags, not commit
  SHAs — no live lookup available this session to verify real SHAs;
  flagged as a known limitation in both workflow files and tracked via
  Dependabot. Tightening to SHA pins is explicit follow-up work, not done
  here to avoid fabricating a hash.
- `mise.toml` tool version pins are a best-effort snapshot, explicitly
  flagged as needing a `research-brief`/Perplexity check before being
  trusted, rather than presented as freshly verified.

## Notes

- Original `docs/homelab-architecture.docx` (containing the real router
  model and real LAN CIDR) is **kept in the repo** as the historical
  source, per user decision not to rewrite history for this content — but
  it is now superseded by `docs/architecture/*.md` as the maintained
  source of truth. See `docs/security/public-repository.md` for why the
  real details in it aren't treated as a blocking secret (not
  credentials) but also aren't propagated into any new file.
