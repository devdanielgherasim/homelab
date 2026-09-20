#!/usr/bin/env bash
# Add, move or remove a Kubernetes worker with one command. The workers are the `workers` map of
# tofu/environments/homelab/terraform.tfvars (private); this script edits it, shows what OpenTofu
# would do, asks once, and then does everything else: the node is drained, the VM is created or
# removed on the right Proxmox host, the guest is prepared and joined, and the result is checked.
#
# Usage:
#   scripts/worker.sh list
#   scripts/worker.sh add <name> [--node <proxmox-node>] [--memory MiB] [--cores N] [--disk GB]
#                                [--vmid ID] [--ip CIDR]
#   scripts/worker.sh move <name> --node <proxmox-node> [--destroy-old]
#   scripts/worker.sh remove <name>
# Options for all: --yes (do not ask), --force (go on when the capacity check fails).
#
# add      The VMID and address are the next free ones unless given. Without --node the worker goes
#          on the primary Proxmox node. Then: plan, one question, VM, guest, join, check.
# move     Drain and delete the Kubernetes node, shut the old VM down (it stays, stopped and
#          protected, on the old host until --destroy-old or until you remove it), create the VM
#          on the new node with the same name, VMID and address, join it, check it.
# remove   Drain and delete the Kubernetes node, then remove the VM.
#
# The node of every worker is a Proxmox node known to OpenTofu: the primary one, or one added with
# scripts/proxmox-node.sh. This script needs the same things as scripts/bootstrap.sh (see there);
# it does not need a token. Ansible reaches the Proxmox hosts as root with the admin key.

set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ssh_key=${HOMELAB_SSH_KEY:-$HOME/.ssh/homelab_admin_ed25519}
export KUBECONFIG=${HOMELAB_KUBECONFIG:-$HOME/.kube/homelab.conf}
config="python3 $repo_root/scripts/lib/homelab_config.py"
tfvars=${HOMELAB_TFVARS:-$repo_root/tofu/environments/homelab/terraform.tfvars}
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
export ANSIBLE_SSH_COMMON_ARGS="-o StrictHostKeyChecking=accept-new"
# Proxmox memory kept for the host itself (measured: about 1.5 GiB idle on Proxmox VE 9).
host_reserve_mib=1700

assume_yes=0
force=0
destroy_old=0
node=""
extra=()
positional=()

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) assume_yes=1 ;;
    --force) force=1 ;;
    --destroy-old) destroy_old=1 ;;
    --node) node=${2:?--node needs a value}; shift ;;
    --memory | --cores | --disk | --vmid | --ip) extra+=("$1" "${2:?$1 needs a value}"); shift ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) positional+=("$1") ;;
  esac
  shift
done
[ ${#positional[@]} -ge 1 ] || { usage >&2; exit 2; }
command_name=${positional[0]}
name=${positional[1]:-}

confirm() {
  [ "$assume_yes" -eq 1 ] && return 0
  read -r -p "$1 [y/N] " answer
  [ "$answer" = "y" ] || die "stopped, nothing was changed beyond what is listed above"
}

ansible_inv() { (cd "$repo_root/ansible" && ansible-inventory -i inventories/production/ "$@"); }
inv_var() { ansible_inv --host "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$2"; }
proxmox_addr() { inv_var "$1" ansible_host; }
pve() { local host=$1; shift; ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$ssh_key" "root@$(proxmox_addr "$host")" "$@"; }
primary_node() { sed -n 's/^proxmox_node_name *= *"\([^"]*\)".*/\1/p' "$tfvars" | head -n1; }

# What the plan would do, without applying it.
preview() {
  log "what OpenTofu would do"
  "$repo_root/scripts/bootstrap.sh" vms --plan-only 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' |
    grep -E '^\s*# module\.|^Plan:|^Error|has moved|will be|must be replaced|Invalid' || true
}

# Refuse a node that cannot hold the worker: memory of the VMs already there plus this one,
# against the host's memory minus what Proxmox itself needs.
capacity_check() {
  local host=$1 memory=$2 total used
  total=$(pve "$host" "free -m | awk '/^Mem:/{print \$2}'")
  used=$(pve "$host" "qm list | awk 'NR>1 && \$1<9000 {s+=\$4} END{print s+0}'")
  echo "capacity on $host: ${used} MiB in VMs + ${memory} MiB new, of $((total - host_reserve_mib)) MiB usable (${total} MiB total)"
  if [ $((used + memory)) -gt $((total - host_reserve_mib)) ]; then
    [ "$force" -eq 1 ] && { echo "over capacity, going on because of --force"; return 0; }
    die "not enough memory on $host for this worker; lower --memory, choose another node, or use --force"
  fi
}

worker_field() { $config workers list | awk -v n="$1" -v k="$2" '$1==n {for(i=2;i<=NF;i++){split($i,a,"="); if(a[1]==k) print a[2]}}'; }

wait_for_node_ready() {
  log "waiting for $1 to be Ready"
  for _ in $(seq 1 60); do
    if [ "$(kubectl get node "$1" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; then
      kubectl get node "$1" -o wide --no-headers | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g'
      return 0
    fi
    sleep 10
  done
  die "$1 did not become Ready within 10 minutes"
}

drain_and_delete_node() {
  log "draining $1 (its pods move to the other workers)"
  kubectl cordon "$1"
  kubectl drain "$1" --ignore-daemonsets --delete-emptydir-data --timeout=300s
  local bad=1
  for _ in $(seq 1 30); do
    bad=$(kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"' | wc -l)
    [ "$bad" -eq 0 ] && break
    sleep 10
  done
  [ "$bad" -eq 0 ] || die "pods are not ready after the drain; $1 is cordoned, not deleted (kubectl uncordon $1 undoes it)"
  kubectl delete node "$1"
}

# The state address of a worker, wherever it is now.
state_address() {
  (cd "$repo_root/tofu/environments/homelab" && env -u TF_ENCRYPTION tofu state list) |
    grep -F "[\"$1\"]" | head -n1
}

snapshot=""
take_snapshot() { snapshot=$(mktemp); cp "$tfvars" "$snapshot"; }
restore_snapshot() { [ -n "$snapshot" ] && cp "$snapshot" "$tfvars" && echo "terraform.tfvars restored"; }

run_stages() {
  "$repo_root/scripts/bootstrap.sh" --yes "$@"
}

case "$command_name" in
  list)
    $config workers list
    ;;

  add)
    [ -n "$name" ] || die "usage: worker.sh add <name> [options]"
    target=${node:-$(primary_node)}
    args=()
    [ -n "$node" ] && args+=(--node "$node")
    take_snapshot
    $config workers add "$name" "${args[@]}" "${extra[@]}"
    trap 'restore_snapshot' ERR
    capacity_check "$target" "$(worker_field "$name" memory)"
    preview
    confirm "Create $name on $target and join it to the cluster?"
    trap - ERR
    run_stages vms guests cluster host
    wait_for_node_ready "$name"
    log "$name is part of the cluster"
    ;;

  remove)
    [ -n "$name" ] || die "usage: worker.sh remove <name>"
    vmid=$(inv_var "$name" vmid); host=$(inv_var "$name" proxmox_host)
    [ -n "$vmid" ] && [ -n "$host" ] || die "$name is not in the inventory (is it applied?)"
    take_snapshot
    $config workers remove "$name"
    trap 'restore_snapshot' ERR
    preview
    confirm "Drain and delete $name, then destroy VM $vmid on $host?"
    trap - ERR
    drain_and_delete_node "$name"
    pve "$host" "qm set $vmid --protection 0" >/dev/null
    run_stages vms
    log "$name is gone"
    ;;

  move)
    [ -n "$name" ] && [ -n "$node" ] || die "usage: worker.sh move <name> --node <proxmox-node> [--destroy-old]"
    vmid=$(inv_var "$name" vmid); old_host=$(inv_var "$name" proxmox_host)
    [ -n "$vmid" ] && [ -n "$old_host" ] || die "$name is not in the inventory (is it applied?)"
    [ "$node" != "$old_host" ] || die "$name is already on $node"
    if [ "$node" = "$(primary_node)" ]; then new_value="-"; else new_value=$node; fi
    capacity_check "$node" "$(worker_field "$name" memory)"
    address=$(state_address "$name") || true
    [ -n "$address" ] || die "$name is not in the OpenTofu state"
    take_snapshot
    $config workers set-node "$name" "$new_value"
    trap 'restore_snapshot' ERR
    preview
    echo "(the plan shows the old VM as destroyed: it is taken out of the state first, and stays on $old_host, stopped)"
    confirm "Move $name from $old_host to $node (same name, VMID $vmid and address)?"
    trap - ERR
    drain_and_delete_node "$name"
    log "shutting the old VM $vmid down on $old_host and keeping it there, stopped"
    pve "$old_host" "qm shutdown $vmid --timeout 120 || qm stop $vmid; qm set $vmid --onboot 0" >/dev/null
    (cd "$repo_root/tofu/environments/homelab" && env -u TF_ENCRYPTION tofu state rm "$address")
    run_stages vms guests cluster host
    wait_for_node_ready "$name"
    if [ "$destroy_old" -eq 1 ]; then
      log "destroying the old VM $vmid on $old_host"
      pve "$old_host" "qm set $vmid --protection 0 && qm destroy $vmid --purge --destroy-unreferenced-disks 1" >/dev/null
    else
      echo "The old VM $vmid is still on $old_host, stopped and protected. Once you have checked $name:"
      echo "  ssh root@<$old_host> 'qm set $vmid --protection 0 && qm destroy $vmid --purge'"
    fi
    log "$name now runs on $node"
    ;;

  *)
    die "unknown command: $command_name (list, add, move, remove)"
    ;;
esac
