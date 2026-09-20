#!/usr/bin/env python3
"""Ansible inventory for the lab VMs, built from OpenTofu's `nodes` output.

OpenTofu is the only place that knows which VMs exist, what role each has and
what address it uses. This script turns that into inventory groups, so adding or
removing a worker (an entry in the `workers` map) needs no change in Ansible.

Groups:
  homelab_vms          every VM
  vpn_gateway          the Tailscale gateway
  k8s_control_plane    the control-plane node(s)
  k8s_workers          the workers
  k8s_nodes            control plane and workers

Host variables: ansible_host, ansible_user, vmid, node_role and proxmox_host (the Proxmox
node the VM is on, which is also that host's name in the static inventory; left out when
the OpenTofu state predates it).

The Proxmox hosts are not VMs and stay in the static hosts.yml next to this file
(Ansible reads both). The script only reads OpenTofu's state; it never contacts
Proxmox and needs no credentials.

Environment:
  TOFU_BIN          the OpenTofu executable (default: tofu)
  TOFU_NODES_JSON   use this JSON instead of asking OpenTofu (used by the tests
                    and for a dry run before the output exists in state)
"""

import json
import os
import subprocess
import sys
from pathlib import Path

TOFU_DIR = Path(__file__).resolve().parents[3] / "tofu" / "environments" / "homelab"

# Which groups a node belongs to, by its role.
ROLE_GROUPS = {
    "vpn": ["vpn_gateway"],
    "control-plane": ["k8s_control_plane", "k8s_nodes"],
    "worker": ["k8s_workers", "k8s_nodes"],
}

SSH_USER = "ubuntu"


def load_nodes():
    raw = os.environ.get("TOFU_NODES_JSON")
    if raw:
        return json.loads(raw)
    tofu = os.environ.get("TOFU_BIN", "tofu")
    result = subprocess.run(
        [tofu, "-chdir=" + str(TOFU_DIR), "output", "-json", "nodes"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        sys.exit("tofu_inventory: `tofu output -json nodes` failed: " + result.stderr.strip())
    return json.loads(result.stdout)


def build(nodes):
    inventory = {"_meta": {"hostvars": {}}, "homelab_vms": {"hosts": []}}
    for name in sorted(nodes):
        node = nodes[name]
        role = node["role"]
        if role not in ROLE_GROUPS:
            sys.exit("tofu_inventory: node %s has an unknown role %r" % (name, role))
        inventory["_meta"]["hostvars"][name] = {
            # OpenTofu stores the address in CIDR form; Ansible needs the bare address.
            "ansible_host": node["ip_address"].split("/")[0],
            "ansible_user": SSH_USER,
            "vmid": node["vm_id"],
            "node_role": role,
        }
        if node.get("proxmox_host"):
            inventory["_meta"]["hostvars"][name]["proxmox_host"] = node["proxmox_host"]
        inventory["homelab_vms"]["hosts"].append(name)
        for group in ROLE_GROUPS[role]:
            inventory.setdefault(group, {"hosts": []})["hosts"].append(name)
    return inventory


def main(argv):
    if len(argv) == 2 and argv[1] == "--list":
        print(json.dumps(build(load_nodes()), indent=2, sort_keys=True))
    elif len(argv) == 3 and argv[1] == "--host":
        print(json.dumps({}))  # everything is in _meta.hostvars
    else:
        sys.exit("usage: tofu_inventory.py --list | --host <name>")


if __name__ == "__main__":
    main(sys.argv)
