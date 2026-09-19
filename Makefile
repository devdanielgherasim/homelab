# Developer/CI entrypoint. Requires a POSIX shell + the tools in mise.toml.
# Runs natively on Linux/WSL2/macOS/CI; on Windows use WSL2 — see
# docs/contributing/development-workflow.md.
#
# Change-aware by design: fmt/lint/validate operate on files changed
# relative to $(BASE_REF), not the whole repository, per AGENTS.md's
# context-efficiency and CI-cost principles. Override with FILES=... to
# force a specific set, or ALL=1 to force whole-repo.

SHELL := /usr/bin/env bash
BASE_REF ?= origin/main
ALL ?=

.DEFAULT_GOAL := help

.PHONY: help doctor fmt lint validate security drift changed-files test-roles

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

doctor: ## Report tool presence/version drift (installs nothing)
	@bash scripts/doctor.sh

changed-files: ## List files changed vs BASE_REF (debug helper)
	@git diff --name-only --diff-filter=ACMR $(BASE_REF)...HEAD 2>/dev/null || git diff --name-only --diff-filter=ACMR HEAD

fmt: ## Format changed files by domain
	@files="$(FILES)"; \
	if [ -z "$$files" ]; then files=$$($(MAKE) -s changed-files); fi; \
	tf=$$(echo "$$files" | grep -E '\.tf$$' || true); \
	if [ -n "$$tf" ] && command -v tofu >/dev/null 2>&1; then \
		echo "-- tofu fmt --"; echo "$$tf" | xargs -r -n1 dirname | sort -u | xargs -r -I{} tofu fmt {}; \
	fi; \
	echo "fmt: done (tofu only; other domains have no formatter yet)"

lint: ## Lint changed files by domain
	@files="$(FILES)"; \
	if [ -z "$$files" ]; then files=$$($(MAKE) -s changed-files); fi; \
	yml=$$(echo "$$files" | grep -E '\.ya?ml$$' || true); \
	sh=$$(echo "$$files" | grep -E '\.sh$$' || true); \
	md=$$(echo "$$files" | grep -E '\.md$$' || true); \
	if [ -n "$$yml" ] && command -v yamllint >/dev/null 2>&1; then echo "-- yamllint --"; echo "$$yml" | xargs -r yamllint -c .yamllint.yaml; fi; \
	if [ -n "$$sh" ] && command -v shellcheck >/dev/null 2>&1; then echo "-- shellcheck --"; echo "$$sh" | xargs -r shellcheck; fi; \
	if [ -n "$$md" ] && command -v markdownlint >/dev/null 2>&1; then echo "-- markdownlint --"; echo "$$md" | xargs -r markdownlint -c .markdownlint.jsonc; fi; \
	echo "lint: done"

validate: lint ## Static validation for changed files (fmt-check + domain validators)
	@files="$(FILES)"; \
	if [ -z "$$files" ]; then files=$$($(MAKE) -s changed-files); fi; \
	tf=$$(echo "$$files" | grep -E '\.tf$$' || true); \
	k8s=$$(echo "$$files" | grep -E '^kubernetes/.*\.ya?ml$$' || true); \
	ans=$$(echo "$$files" | grep -E '^ansible/' || true); \
	if [ -n "$$tf" ] && command -v tofu >/dev/null 2>&1; then \
		echo "-- tofu fmt -check / validate --"; \
		echo "$$tf" | xargs -r -n1 dirname | sort -u | while read -r d; do (cd "$$d" && tofu fmt -check && tofu init -backend=false -input=false >/dev/null && tofu validate); done; \
	fi; \
	if [ -n "$$k8s" ] && command -v kubeconform >/dev/null 2>&1; then \
		echo "-- kubeconform --"; echo "$$k8s" | xargs -r kubeconform -strict -summary -ignore-filename-pattern '(^|/)values[^/]*[.]ya?ml$$'; \
	fi; \
	if [ -n "$$ans" ] && command -v ansible-lint >/dev/null 2>&1; then \
		echo "-- ansible-lint --"; ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint; \
	fi; \
	echo "validate: done"

security: ## Local secret scan + IaC security scan
	@if command -v gitleaks >/dev/null 2>&1; then \
		echo "-- gitleaks --"; gitleaks detect --source . --no-git -v || gitleaks detect --source . -v; \
	else echo "gitleaks not installed — see 'make doctor'"; fi
	@if command -v trivy >/dev/null 2>&1; then \
		echo "-- trivy config --"; trivy config --exit-code 0 tofu ansible kubernetes 2>/dev/null || true; \
	else echo "trivy not installed — see 'make doctor'"; fi

test-roles: ## Converge-test Ansible roles in a throwaway container (needs Docker)
	@bash scripts/test-roles.sh

drift: ## Report drift between declared (Git) and actual infra state — non-mutating
	@if [ -z "$$(find tofu -mindepth 2 -name '*.tf' 2>/dev/null)" ]; then \
		echo "tofu: no modules yet — nothing to check (see STATUS.md)"; \
	else \
		echo "-- tofu plan -detailed-exitcode --"; \
		find tofu/environments -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do (cd "$$d" && tofu plan -detailed-exitcode -input=false) ; done; \
	fi
	@if [ -z "$$(find ansible/playbooks -name '*.yml' 2>/dev/null)" ]; then \
		echo "ansible: no playbooks yet — nothing to check (see STATUS.md)"; \
	else \
		echo "-- ansible-playbook --check --diff --"; \
		find ansible/playbooks -name '*.yml' | xargs -r -n1 ansible-playbook --check --diff; \
	fi

# --- Infrastructure-changing targets: intentionally not implemented yet. ---
# Adding make infra-plan / infra-apply / cluster / bootstrap here is future
# work, gated on tofu/ and ansible/ having real content — see STATUS.md and
# AGENTS.md's destructive-action policy. When added, apply/destroy targets
# must require explicit confirmation and never be reachable from a hook or
# CI trigger tied to untrusted input.
