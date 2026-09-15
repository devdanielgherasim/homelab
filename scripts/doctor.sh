#!/usr/bin/env bash
# scripts/doctor.sh — reports tool presence/version drift. Installs nothing.
# Run via `make doctor`. Intended for WSL2/Linux; see docs/contributing/development-workflow.md.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISE_TOML="$REPO_ROOT/mise.toml"

missing=0
present=0

check() {
  local name="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local version
    version="$("$cmd" --version 2>&1 | head -n1)"
    printf "  OK   %-14s %s\n" "$name" "$version"
    present=$((present + 1))
  else
    printf "  MISS %-14s not found on PATH\n" "$name"
    missing=$((missing + 1))
  fi
}

echo "== Required tooling (see mise.toml for pinned versions) =="
check "git"          git
check "gh"           gh
check "tofu"         tofu
check "kubectl"      kubectl
check "helm"         helm
check "sops"         sops
check "age"          age
check "trivy"        trivy
check "yamllint"     yamllint
check "shellcheck"   shellcheck
check "gitleaks"     gitleaks
check "kubeconform"  kubeconform
check "ansible"      ansible
check "ansible-lint" ansible-lint
check "pre-commit"   pre-commit
check "mise"         mise

echo
echo "== Environment =="
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "  Running inside WSL2 — correct environment for make targets."
else
  case "$(uname -s)" in
    Linux)  echo "  Running on native Linux." ;;
    Darwin) echo "  Running on macOS." ;;
    *)      echo "  WARNING: not Linux/WSL2/macOS — Ansible and most make targets need one of these. See docs/contributing/development-workflow.md." ;;
  esac
fi

echo
echo "== Summary =="
echo "  $present present, $missing missing."
if [ "$missing" -gt 0 ]; then
  echo "  Install missing tools with: mise install (after 'mise use' picks up mise.toml)"
  echo "  or see docs/contributing/development-workflow.md for manual install commands."
  exit 1
fi
echo "  All required tools present."
exit 0
