#!/usr/bin/env bash
# Builds the whole cluster from a Proxmox host that is already installed and bootstrapped
# (playbooks/proxmox-bootstrap.yml, playbooks/proxmox-template.yml): VMs, node preparation,
# kubeadm, kubeconfig, then the platform stage (Cilium, Argo CD, secrets). After the last
# stage Argo CD installs everything else from Git. See ADR-0016.
#
# Usage:
#   scripts/bootstrap.sh [--yes] [--plan-only] [stage ...]
#
# Stages, in the order they run when none is named:
#   vms         tofu/environments/homelab: create the VMs
#   guests      guest agent and SSH/unattended-upgrades hardening on every VM
#   cluster     containerd, kubeadm, control plane, workers, etcd snapshots
#   host        boot order and the vzdump job, on the Proxmox host
#   kubeconfig  fetch the kubeconfig to a private local path
#   platform    tofu/environments/platform: Cilium, Argo CD, secrets
# Not in the default chain: `vpn` (Tailscale; needs a one-time auth key in a root-only file,
# see ansible/playbooks/tailscale.yml).
#
# Every `tofu apply` shows its plan and asks before it applies (--yes skips the question,
# --plan-only stops after the plan). Ansible stages are idempotent and run without a prompt.
#
# The order of guests, cluster, host, kubeconfig and platform was proven on 2026-09-20 by
# rebuilding the cluster from Git (docs/runbooks/rebuild-cluster.md). The vms stage was
# replaced there by a manual `tofu apply -replace`, so it has not been run end to end.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ssh_key=${HOMELAB_SSH_KEY:-$HOME/.ssh/homelab_admin_ed25519}
assume_yes=0
plan_only=0
stages=()

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --yes) assume_yes=1 ;;
    --plan-only) plan_only=1 ;;
    -h | --help) usage; exit 0 ;;
    vms | guests | cluster | host | kubeconfig | platform | vpn) stages+=("$arg") ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done
if [ ${#stages[@]} -eq 0 ]; then stages=(vms guests cluster host kubeconfig platform); fi

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_env() {
  local missing=0 v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then echo "missing environment variable: $v" >&2; missing=1; fi
  done
  [ "$missing" -eq 0 ] || die "set the variables above (see the README of the stage)"
}

# The state encryption of the platform stage must not leak into the other stages: the VM
# state is not encrypted, and the Ansible inventory script reads it with `tofu output`, so
# an enforced TF_ENCRYPTION would make it fail. Keep the value aside and hand it only to the
# platform stage.
platform_encryption=${TF_ENCRYPTION:-}
unset TF_ENCRYPTION

# ansible-playbook with this repository's config and inventory (built from tofu's output).
# ansible.cfg keeps host key checking on. A freshly created VM has a key nobody has seen yet,
# so accept an unknown key on first contact (a key that CHANGED is still refused; the VMs
# this run recreates get their old key removed below).
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
export ANSIBLE_SSH_COMMON_ARGS="-o StrictHostKeyChecking=accept-new"

# Ansible exits 0 when a play matches no host, which would let a stage "succeed" doing nothing
# (for example when the inventory script fails). Refuse to go on with an empty group.
require_hosts() {
  local group=$1
  (cd "$repo_root/ansible" && ansible "$group" -i inventories/production/ --list-hosts 2>/dev/null) |
    grep -qE 'hosts \([1-9]' || die "inventory group '$group' is empty; is the VM stage applied and is tofu's state readable?"
}

play() {
  local playbook=$1
  shift
  (cd "$repo_root/ansible" && ansible-playbook -i inventories/production/ \
    "playbooks/$playbook" --private-key "$ssh_key" "$@")
}

# Names of the VMs that a plan of the homelab stage creates or replaces.
vms_created_by() {
  (cd "$repo_root/tofu/environments/homelab" && tofu show -json "$1") | python3 -c '
import json, re, sys
for rc in json.load(sys.stdin).get("resource_changes", []):
    if rc["type"] == "proxmox_virtual_environment_vm" and "create" in rc["change"]["actions"]:
        m = re.match(r"module\.(?:workers\[\"([^\"]+)\"\]|([a-z0-9]+))\.", rc["address"])
        print(m.group(1) or m.group(2))
'
}

# Remove the old SSH host key of a VM that was just recreated: its key is new by definition.
forget_host_keys_of() {
  local name ip
  (cd "$repo_root/tofu/environments/homelab" && tofu output -json nodes) > "$1.nodes"
  while read -r name; do
    [ -n "$name" ] || continue
    ip=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["ip_address"].split("/")[0])' "$1.nodes" "$name")
    echo "forgetting the old SSH host key of $name ($ip)"
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  done < "$1"
  rm -f "$1.nodes"
}

# plan, show it, ask, apply the plan that was shown.
tofu_stage() {
  local dir=$1 encryption=${2:-} planfile created
  local -a run=(env)
  if [ -n "$encryption" ]; then run+=("TF_ENCRYPTION=$encryption"); fi
  planfile=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$planfile'" RETURN
  (
    cd "$repo_root/$dir"
    "${run[@]}" tofu init -input=false >/dev/null
    "${run[@]}" tofu plan -input=false -out="$planfile"
  )
  if [ "$plan_only" -eq 1 ]; then echo "(plan only: not applying)"; return 0; fi
  if [ "$assume_yes" -ne 1 ]; then
    read -r -p "Apply this plan for $dir? [y/N] " answer
    [ "$answer" = "y" ] || die "not applied"
  fi
  if [ "$dir" = "tofu/environments/homelab" ]; then
    created=$(mktemp)
    vms_created_by "$planfile" > "$created"
  fi
  (
    cd "$repo_root/$dir"
    "${run[@]}" tofu apply -input=false "$planfile"
  )
  if [ -n "${created:-}" ]; then
    forget_host_keys_of "$created"
    rm -f "$created"
  fi
}

wait_for_ssh() {
  log "waiting for every VM to accept SSH (cloud-init needs a minute after the first boot)"
  for _ in $(seq 1 40); do
    if (cd "$repo_root/ansible" && ansible homelab_vms -i inventories/production/ \
      -m ansible.builtin.ping --private-key "$ssh_key" >/dev/null 2>&1); then
      echo "all VMs answer"
      return 0
    fi
    sleep 15
  done
  die "VMs did not become reachable within 10 minutes"
}

for stage in "${stages[@]}"; do
  case "$stage" in
    vms)
      log "stage vms: OpenTofu creates the VMs"
      need_env PROXMOX_VE_ENDPOINT PROXMOX_VE_API_TOKEN
      tofu_stage tofu/environments/homelab
      ;;
    guests)
      log "stage guests: guest agent and hardening"
      require_hosts homelab_vms
      wait_for_ssh
      play guest-agent.yml
      play guest-hardening.yml
      ;;
    cluster)
      log "stage cluster: containerd, kubeadm, control plane, workers, etcd snapshots"
      require_hosts k8s_control_plane
      play k8s-bootstrap.yml
      play etcd-backup.yml
      ;;
    host)
      log "stage host: boot order and vzdump job on the Proxmox host"
      require_hosts proxmox
      play proxmox-vm-startup.yml
      play proxmox-backup.yml
      ;;
    kubeconfig)
      log "stage kubeconfig: fetch it to a private local path"
      require_hosts k8s_control_plane
      play k8s-kubeconfig.yml
      ;;
    platform)
      log "stage platform: Cilium, Argo CD, generated secrets"
      [ -n "$platform_encryption" ] || die "set TF_ENCRYPTION (see tofu/environments/platform/encryption.example)"
      tofu_stage tofu/environments/platform "$platform_encryption"
      ;;
    vpn)
      log "stage vpn: Tailscale subnet router"
      require_hosts vpn_gateway
      play tailscale.yml
      ;;
  esac
done

log "done: ${stages[*]}"
