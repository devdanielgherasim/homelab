#!/usr/bin/env bash
# scripts/doctor.sh — reports tool presence/version drift. Installs nothing.
# Run via `make doctor`. Intended for WSL2/Linux; see docs/contributing/development-workflow.md.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISE_TOML="$REPO_ROOT/mise.toml"

missing=0
present=0
drift=0

# Version pinned for a tool in mise.toml (empty if the tool is not pinned).
pinned_version() {
  sed -nE "s/^\"?$1\"?[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" "$MISE_TOML" | head -n1
}

check() {
  local name="$1" cmd="$2" mise_key="${4:-$2}"
  # Optional $3: version invocation args (some tools don't take --version —
  # kubectl/helm use a `version` subcommand, kubeconform uses -v, both
  # confirmed against real installs, not guessed).
  local version_args="${3:---version}"
  if command -v "$cmd" >/dev/null 2>&1; then
    local full version want
    # shellcheck disable=SC2086 # word-splitting is intentional here
    full="$("$cmd" $version_args 2>&1 | head -n5)"
    version="$(head -n1 <<<"$full")"
    want="$(pinned_version "$mise_key")"
    # Compare against the first lines, not just the one shown: some tools
    # (shellcheck) print the version on a later line.
    if [ -n "$want" ] && [[ "$full" != *"$want"* ]]; then
      printf "  DRIFT %-13s %s (mise.toml pins %s)\n" "$name" "$version" "$want"
      drift=$((drift + 1))
    else
      printf "  OK   %-14s %s\n" "$name" "$version"
    fi
    present=$((present + 1))
  else
    printf "  MISS %-14s not found on PATH\n" "$name"
    missing=$((missing + 1))
  fi
}

echo "== Required tooling (see mise.toml for pinned versions) =="
check "git"          git
check "gh"           gh
check "tofu"         tofu         "--version" opentofu
check "kubectl"      kubectl      "version --client"
check "helm"         helm         "version"
check "sops"         sops
check "age"          age
check "trivy"        trivy
check "yamllint"     yamllint
check "shellcheck"   shellcheck
check "gitleaks"     gitleaks
check "kubeconform"  kubeconform  "-v"
check "ansible"      ansible      "--version" "pipx:ansible-core"
check "ansible-lint" ansible-lint "--version" "pipx:ansible-lint"
check "pre-commit"   pre-commit   "--version" "pipx:pre-commit"
check "mise"         mise
check "pipx"         pipx

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
echo "  $present present, $missing missing, $drift differing from mise.toml."
if [ "$missing" -gt 0 ]; then
  echo "  Install missing tools with: mise install (after 'mise use' picks up mise.toml)"
  echo "  or see docs/contributing/development-workflow.md for manual install commands."
  exit 1
fi
echo "  All required tools present."
exit 0
