#!/usr/bin/env bash
# Add another standalone Proxmox node to the lab with one command. Install Proxmox VE on the
# machine first (from the ISO: that is the one step no script can do), give it a static address,
# then run this. Nothing else is done by hand: the node is added to the Ansible inventory and to
# OpenTofu, prepared with the safe bootstrap stages, and checked. After that a worker can be
# placed on it with scripts/worker.sh.
#
# Usage:
#   scripts/proxmox-node.sh add <name> <ip> [--slot 1|2|3] [--yes]
#   scripts/proxmox-node.sh list
#
#   <name>  the node's name, as Proxmox knows it (`hostname`), for example pve02
#   <ip>    its management address
#
# What `add` does, after one question:
#   1. installs the admin SSH key on the node, if it is not there yet (asks for the root password
#      once, in your terminal: the only credential the script ever sees);
#   2. adds the node to the static inventory and to `proxmox_nodes` (private files, copies kept);
#   3. runs the safe stages of playbooks/proxmox-bootstrap.yml on it: network check, SSH key,
#      firewall allow rules (the policy stays permissive), its CA into the bundle of all nodes;
#   4. builds the Ubuntu cloud-init VM template (VMID 9000) on it;
#   5. checks that OpenTofu reaches it (a temporary session, then a plan) and that TLS verifies.
# It does NOT run firewall_enforce or ssh_lockdown: they can lock you out of the machine, so they
# stay a separate decision (see playbooks/proxmox-bootstrap.yml).
#
# A node has its own CA, its own storage and its own memory: a worker's VMID and address stay the
# ones in the `workers` map, wherever it runs. Up to three extra nodes (see var.proxmox_nodes).

set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ssh_key=${HOMELAB_SSH_KEY:-$HOME/.ssh/homelab_admin_ed25519}
config="python3 $repo_root/scripts/lib/homelab_config.py"
tfvars=${HOMELAB_TFVARS:-$repo_root/tofu/environments/homelab/terraform.tfvars}
inventory=${HOMELAB_INVENTORY:-$repo_root/ansible/inventories/production/hosts.yml}
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
export ANSIBLE_SSH_COMMON_ARGS="-o StrictHostKeyChecking=accept-new"
config_dir=${HOMELAB_CONFIG_DIR:-$HOME/.config/homelab}

assume_yes=0
slot_args=()
positional=()

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) assume_yes=1 ;;
    --slot) slot_args=(--slot "${2:?--slot needs a value}"); shift ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) positional+=("$1") ;;
  esac
  shift
done
[ ${#positional[@]} -ge 1 ] || { usage >&2; exit 2; }

play() {
  local playbook=$1
  shift
  (cd "$repo_root/ansible" && ansible-playbook -i inventories/production/ "playbooks/$playbook" \
    --private-key "$ssh_key" "$@")
}

case "${positional[0]}" in
  list)
    (cd "$repo_root/ansible" && ansible-inventory -i inventories/production/hosts.yml --list |
      python3 -c 'import json,sys; d=json.load(sys.stdin); [print(h, d["_meta"]["hostvars"][h]["ansible_host"]) for h in d["proxmox"]["hosts"]]')
    echo "-- extra nodes known to OpenTofu:"
    $config nodes list
    ;;

  add)
    name=${positional[1]:-}
    ip=${positional[2]:-}
    [ -n "$name" ] && [ -n "$ip" ] || die "usage: proxmox-node.sh add <name> <ip> [--slot N]"
    [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || die "the node name is lowercase letters, digits and hyphens"
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the address must be an IPv4 address"
    [ -f "$ssh_key.pub" ] || die "no admin public key at $ssh_key.pub"

    echo "This will add the Proxmox node $name ($ip):"
    echo "  - install the admin SSH key on it (root password asked once, if the key is not there)"
    echo "  - add it to the Ansible inventory and to proxmox_nodes (private files; copies are kept)"
    echo "  - bootstrap: network check, SSH key, firewall allow rules (permissive), CA, VM template 9000"
    echo "  - no firewall enforcement and no SSH lockdown"
    if [ "$assume_yes" -ne 1 ]; then
      read -r -p "Go on? [y/N] " answer
      [ "$answer" = "y" ] || die "stopped, nothing was changed"
    fi

    log "SSH key on $name"
    if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -i "$ssh_key" "root@$ip" true 2>/dev/null; then
      [ -t 0 ] || die "the admin key is not on $name yet, and there is no terminal to ask for the root password; run: ssh-copy-id -i $ssh_key.pub root@$ip"
      ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$ssh_key.pub" "root@$ip"
      ssh -o BatchMode=yes -i "$ssh_key" "root@$ip" true || die "key login to $name still fails"
    fi
    remote_name=$(ssh -o BatchMode=yes -i "$ssh_key" "root@$ip" hostname)
    [ "$remote_name" = "$name" ] || die "the machine at $ip is called $remote_name, not $name: the name has to match (OpenTofu uses it as the Proxmox node name)"

    log "inventory and OpenTofu"
    inventory_copy=$(mktemp)
    tfvars_copy=$(mktemp)
    cp "$inventory" "$inventory_copy"
    cp "$tfvars" "$tfvars_copy"
    if ! { $config hosts add "$name" "$ip" && $config nodes add "$name" "https://$ip:8006/" "${slot_args[@]}"; }; then
      cp "$inventory_copy" "$inventory"
      cp "$tfvars_copy" "$tfvars"
      die "could not add the node; the files are as they were"
    fi

    log "bootstrap: the safe stages, one after the other"
    for tag in network_check ssh_key_add firewall_rules tls_ca; do
      echo "-- $tag"
      play proxmox-bootstrap.yml --tags "$tag" --limit "$name" >/dev/null ||
        die "stage $tag failed on $name (run it alone to see why: ansible-playbook playbooks/proxmox-bootstrap.yml --tags $tag --limit $name)"
    done

    log "VM template on $name"
    play proxmox-template.yml --limit "$name" >/dev/null || die "the template build failed on $name"

    log "checking that OpenTofu reaches every node"
    bundle=$config_dir/pve-root-ca-bundle.pem
    code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$bundle" "https://$ip:8006/api2/json/version" || true)
    [ "$code" = "401" ] || [ "$code" = "200" ] || die "TLS to $name does not verify against $bundle (HTTP $code)"
    echo "TLS verifies against the bundle"
    "$repo_root/scripts/bootstrap.sh" vms --plan-only 2>&1 | grep -E '^Plan:|No changes|^Error' || true

    log "node $name is ready"
    echo "Place a worker on it:   scripts/worker.sh add worker03 --node $name"
    echo "Move one to it:         scripts/worker.sh move worker02 --node $name"
    echo "Harden it, when you are ready (can lock you out; keep the console at hand):"
    echo "  ansible-playbook playbooks/proxmox-bootstrap.yml --tags ssh_lockdown --limit $name"
    ;;

  *)
    die "unknown command: ${positional[0]} (add, list)"
    ;;
esac
