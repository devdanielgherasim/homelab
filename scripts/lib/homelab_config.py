#!/usr/bin/env python3
"""Edit the private configuration files of the lab: the OpenTofu variables (terraform.tfvars)
and the Ansible inventory of Proxmox hosts (hosts.yml).

Used by scripts/worker.sh and scripts/proxmox-node.sh so that adding a worker or a Proxmox node
is one command and nobody edits HCL or YAML by hand. Both files are private (gitignored); a copy
of each is kept before it is changed.

The two blocks it edits are written one entry per line, as terraform.tfvars.example shows:

    workers = {
      worker01 = { vmid = 103, ip_address = "10.10.10.13/24" }
    }
    proxmox_nodes = {
      pve02 = { endpoint = "https://10.10.10.20:8006/", slot = 1 }
    }

Anything else in the file is left exactly as it is.

Usage:
  homelab_config.py workers list
  homelab_config.py workers add NAME [--node N] [--vmid ID] [--ip CIDR] [--cores C] [--memory MiB] [--disk GB]
  homelab_config.py workers remove NAME
  homelab_config.py workers set-node NAME NODE        (NODE "-" = the primary node)
  homelab_config.py nodes list
  homelab_config.py nodes add NAME ENDPOINT [--slot N]
  homelab_config.py hosts add NAME IP                 (the static Ansible inventory)

Environment: HOMELAB_TFVARS, HOMELAB_INVENTORY override the two paths.
"""

import argparse
import ipaddress
import os
import re
import shutil
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TFVARS = Path(os.environ.get("HOMELAB_TFVARS", REPO / "tofu/environments/homelab/terraform.tfvars"))
INVENTORY = Path(os.environ.get("HOMELAB_INVENTORY", REPO / "ansible/inventories/production/hosts.yml"))

ENTRY = re.compile(r"^(\s*)([a-z][a-z0-9-]*)\s*=\s*\{(.*)\}\s*(#.*)?$")
WORKER_KEYS = ["vmid", "ip_address", "node", "cores", "memory", "disk_size"]


def die(message):
    sys.exit("error: " + message)


def backup(path):
    """Keep a copy of a private file before it changes."""
    directory = Path(os.environ.get("HOMELAB_CONFIG_DIR", Path.home() / ".config/homelab")) / "backups"
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    target = directory / ("%s.%s" % (path.name, time.strftime("%Y%m%d-%H%M%S")))
    shutil.copy2(path, target)
    return target


def read_lines(path):
    if not path.exists():
        die("%s does not exist" % path)
    return path.read_text(encoding="utf-8").split("\n")


def write_lines(path, lines):
    backup(path)
    path.write_text("\n".join(lines), encoding="utf-8")


def find_block(lines, name):
    """Return (start, end) of `name = {` ... `}` at column 0, or None."""
    start = next((i for i, l in enumerate(lines) if re.match(r"^%s\s*=\s*\{\s*$" % re.escape(name), l)), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if re.match(r"^\}\s*$", lines[i])), None)
    if end is None:
        die("the block `%s` in %s is not closed" % (name, TFVARS))
    return start, end


def parse_fields(text):
    fields = {}
    for part in re.findall(r'([a-z_]+)\s*=\s*("[^"]*"|[0-9]+)', text):
        key, value = part
        fields[key] = value[1:-1] if value.startswith('"') else int(value)
    return fields


def render_fields(fields, keys):
    out = []
    for key in keys:
        if key in fields and fields[key] is not None:
            value = fields[key]
            out.append("%s = %s" % (key, '"%s"' % value if isinstance(value, str) else value))
    return ", ".join(out)


def entries(lines, block):
    """Map name -> (line index, indent, fields) for the one-line entries of a block."""
    found = find_block(lines, block)
    result = {}
    if found is None:
        return result, None
    for i in range(found[0] + 1, found[1]):
        m = ENTRY.match(lines[i])
        if m:
            result[m.group(2)] = (i, m.group(1), parse_fields(m.group(3)))
        elif lines[i].strip() and not lines[i].strip().startswith("#"):
            die("line %d of %s is not a one-line entry of `%s`; write it as `name = { key = value, ... }`"
                % (i + 1, TFVARS, block))
    return result, found


def scalar(lines, name):
    for l in lines:
        m = re.match(r'^%s\s*=\s*"([^"]*)"' % re.escape(name), l)
        if m:
            return m.group(1)
    return None


# ------------------------------------------------------------------------------ workers
def workers_list(_args):
    lines = read_lines(TFVARS)
    found, _ = entries(lines, "workers")
    primary = scalar(lines, "proxmox_node_name") or "(primary)"
    for name, (_i, _ind, f) in sorted(found.items()):
        print("%-12s vmid=%-4s ip=%-18s node=%-8s cores=%s memory=%s disk=%s" % (
            name, f.get("vmid"), f.get("ip_address"), f.get("node", primary), f.get("cores", 2),
            f.get("memory", 3584), f.get("disk_size", 64)))


def free_vmid(used):
    for vmid in range(103, 200):
        if vmid not in used:
            return vmid
    die("no free VMID left in 103-199")


def free_ip(lines, workers):
    taken = set()
    interfaces = []
    for f in (w[2] for w in workers.values()):
        if f.get("ip_address"):
            interfaces.append(ipaddress.ip_interface(f["ip_address"]))
    for var in ("vpn01_ip", "cp01_ip"):
        value = scalar(lines, var)
        if value:
            interfaces.append(ipaddress.ip_interface(value))
    if not interfaces:
        die("cannot choose an address: give one with --ip")
    network = interfaces[0].network
    taken = {i.ip for i in interfaces}
    last = max(ip for ip in taken if ip in network)
    candidate = last + 1
    while candidate in taken:
        candidate += 1
    if candidate not in network.hosts():
        die("no free address left in %s after %s; give one with --ip" % (network, last))
    return "%s/%d" % (candidate, network.prefixlen)


def check_node(lines, node):
    """A worker's node is the primary Proxmox node or one of proxmox_nodes."""
    if node in (None, "-"):
        return
    known, _ = entries(lines, "proxmox_nodes")
    if node != scalar(lines, "proxmox_node_name") and node not in known:
        die("%s is not a Proxmox node of the lab; add it first with scripts/proxmox-node.sh (known: %s)"
            % (node, ", ".join(sorted([scalar(lines, "proxmox_node_name") or "?"] + list(known)))))


def workers_add(args):
    lines = read_lines(TFVARS)
    check_node(lines, args.node)
    found, block = entries(lines, "workers")
    if block is None:
        die("%s has no `workers = { ... }` block" % TFVARS)
    if not re.match(r"^[a-z][a-z0-9-]*[0-9]$", args.name):
        die("a worker name is lowercase letters, digits and hyphens and ends in a digit (worker03)")
    if args.name in found:
        die("worker %s already exists" % args.name)
    used = {w[2].get("vmid") for w in found.values()}
    vmid = args.vmid or free_vmid(used)
    if vmid in used:
        die("VMID %s is taken" % vmid)
    ip = args.ip or free_ip(lines, found)
    if any(w[2].get("ip_address") == ip for w in found.values()):
        die("address %s is taken" % ip)
    fields = {"vmid": vmid, "ip_address": ip, "node": args.node, "cores": args.cores,
              "memory": args.memory, "disk_size": args.disk}
    indent = next(iter(found.values()))[1] if found else "  "
    lines.insert(block[1], "%s%s = { %s }" % (indent, args.name, render_fields(fields, WORKER_KEYS)))
    write_lines(TFVARS, lines)
    print("added %s: vmid %s, %s%s" % (args.name, vmid, ip, ", node " + args.node if args.node else ""))


def workers_remove(args):
    lines = read_lines(TFVARS)
    found, _ = entries(lines, "workers")
    if args.name not in found:
        die("no worker called %s" % args.name)
    del lines[found[args.name][0]]
    write_lines(TFVARS, lines)
    print("removed %s" % args.name)


def workers_set_node(args):
    lines = read_lines(TFVARS)
    check_node(lines, args.node)
    found, _ = entries(lines, "workers")
    if args.name not in found:
        die("no worker called %s" % args.name)
    i, indent, fields = found[args.name]
    fields["node"] = None if args.node == "-" else args.node
    lines[i] = "%s%s = { %s }" % (indent, args.name, render_fields(fields, WORKER_KEYS))
    write_lines(TFVARS, lines)
    print("%s is now on %s" % (args.name, args.node if args.node != "-" else "the primary node"))


# ------------------------------------------------------------------------------- nodes
def nodes_list(_args):
    found, _ = entries(read_lines(TFVARS), "proxmox_nodes")
    for name, (_i, _ind, f) in sorted(found.items()):
        print("%-10s slot=%s cpu_type=%s" % (name, f.get("slot"), f.get("cpu_type", "x86-64-v2-AES (default)")))


def nodes_add(args):
    lines = read_lines(TFVARS)
    found, block = entries(lines, "proxmox_nodes")
    if args.name in found:
        die("node %s is already in proxmox_nodes" % args.name)
    if scalar(lines, "proxmox_node_name") == args.name:
        die("%s is the primary node" % args.name)
    used = {n[2].get("slot") for n in found.values()}
    slot = args.slot or next((s for s in (1, 2, 3) if s not in used), None)
    if slot is None:
        die("all three provider slots are taken (see var.proxmox_nodes)")
    if slot in used:
        die("slot %s is taken" % slot)
    entry = "  %s = { endpoint = \"%s\", slot = %d }" % (args.name, args.endpoint, slot)
    if block is None:
        lines = [l for l in lines]
        while lines and lines[-1] == "":
            lines.pop()
        lines += ["", "# More standalone Proxmox nodes (ADR-0020). Tokens come from TF_VAR_proxmox_node_tokens.",
                  "proxmox_nodes = {", entry, "}", ""]
    else:
        lines.insert(block[1], entry)
    write_lines(TFVARS, lines)
    print("added node %s in slot %d" % (args.name, slot))


# ------------------------------------------------------------------------------ hosts
def hosts_add(args):
    lines = read_lines(INVENTORY)
    start = next((i for i, l in enumerate(lines) if re.match(r"^proxmox:\s*$", l)), None)
    if start is None:
        die("%s has no `proxmox:` group" % INVENTORY)
    hosts = next((i for i in range(start + 1, len(lines)) if re.match(r"^  hosts:\s*$", lines[i])), None)
    if hosts is None:
        die("the proxmox group in %s has no `hosts:`" % INVENTORY)
    end = hosts + 1
    while end < len(lines) and (lines[end].strip() == "" or len(lines[end]) - len(lines[end].lstrip()) >= 4):
        if re.match(r"^    %s:\s*$" % re.escape(args.name), lines[end]):
            die("host %s is already in the inventory" % args.name)
        end += 1
    while lines[end - 1].strip() == "":
        end -= 1
    lines[end:end] = ["    %s:" % args.name, "      ansible_host: %s" % args.ip, "      ansible_user: root"]
    write_lines(INVENTORY, lines)
    print("added host %s to the inventory" % args.name)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="area", required=True)

    w = sub.add_parser("workers").add_subparsers(dest="cmd", required=True)
    w.add_parser("list").set_defaults(fn=workers_list)
    a = w.add_parser("add")
    a.add_argument("name")
    a.add_argument("--node")
    a.add_argument("--vmid", type=int)
    a.add_argument("--ip")
    a.add_argument("--cores", type=int)
    a.add_argument("--memory", type=int)
    a.add_argument("--disk", type=int)
    a.set_defaults(fn=workers_add)
    r = w.add_parser("remove")
    r.add_argument("name")
    r.set_defaults(fn=workers_remove)
    s = w.add_parser("set-node")
    s.add_argument("name")
    s.add_argument("node")
    s.set_defaults(fn=workers_set_node)

    n = sub.add_parser("nodes").add_subparsers(dest="cmd", required=True)
    n.add_parser("list").set_defaults(fn=nodes_list)
    na = n.add_parser("add")
    na.add_argument("name")
    na.add_argument("endpoint")
    na.add_argument("--slot", type=int)
    na.set_defaults(fn=nodes_add)

    h = sub.add_parser("hosts").add_subparsers(dest="cmd", required=True)
    ha = h.add_parser("add")
    ha.add_argument("name")
    ha.add_argument("ip")
    ha.set_defaults(fn=hosts_add)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
