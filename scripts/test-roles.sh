#!/usr/bin/env bash
# Converge tests for the Ansible roles that can be exercised without real hosts.
#
# Roles are applied inside one throwaway systemd container (never against real
# infrastructure) and each is checked for the same three properties: it reaches
# the intended state, a second run changes nothing (idempotence), and its safety
# checks refuse bad input.
#
#   tofu_inventory   builds the groups and host variables from OpenTofu's `nodes` output,
#                    shows a new worker with no other edit, rejects an unknown role,
#                    and carries the Proxmox host of each VM (`proxmox_host`).
#   proxmox_vm_startup, proxmox_backup  with two standalone Proxmox hosts, each acts only on
#                    the VMs on it (against stand-ins for qm, pvesh and pvesm).
#   proxmox_bootstrap  the temporary OpenTofu session: a private token per host, gone at the end.
#   homelab_config.py  the helper behind worker.sh and proxmox-node.sh edits the workers, the
#                    Proxmox nodes and the inventory hosts, and leaves everything else alone.
#   guest_hardening  beats a cloud-init drop-in, is idempotent, refuses a lock-out.
#   tailscale        installs from the signed repo, enables forwarding, is idempotent,
#                    refuses to run without routes. It never joins a tailnet here.
#   kubelet_server_tls  adds serverTLSBootstrap to the kubelet configuration once, restarts the
#                    kubelet only when it changed, and refreshes the ConfigMap only when needed.
#   etcd_backup      installs the units; the snapshot script keeps exactly N copies,
#                    creates them private, and discards a snapshot that fails
#                    verification (run against stand-ins for etcdctl/etcdutl).
#
# Needs Docker only. Runs the same way locally and in CI.
set -euo pipefail

# Pinned by digest: a moving tag would make this test non-reproducible.
IMAGE="${TEST_IMAGE:-jrei/systemd-ubuntu:24.04@sha256:936c599ab7fb6019ff05ff3845cd7536f991848f8040c51c745931d3a648f144}"
NAME="role-test-$$"
ANSIBLE_CORE_VERSION="2.21.2" # keep in sync with mise.toml

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Git Bash on Windows needs the Windows form of the path for docker -v.
mount_src="$(cd "$repo_root" && (pwd -W 2>/dev/null || pwd))"
export MSYS_NO_PATHCONV=1

logdir="$(mktemp -d)"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$logdir"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# run_playbook <playbook> [ansible-playbook args...]; log goes to $logdir/<name>.log
run_playbook() {
  local playbook="$1"; shift
  docker exec \
    -e ANSIBLE_CONFIG=/repo/ansible/ansible.cfg \
    -e ANSIBLE_LOCAL_TEMP=/tmp/.ansible \
    -e ANSIBLE_NOCOLOR=1 -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
    "$NAME" ansible-playbook -i /tmp/inv.ini "/repo/ansible/playbooks/${playbook}" "$@"
}

# expect_ok <label> <playbook> [args...]: must succeed; on failure print the log.
expect_ok() {
  local label="$1"; shift
  run_playbook "$@" >"$logdir/$label.log" 2>&1 || { cat "$logdir/$label.log"; fail "$label: playbook failed"; }
}

# expect_unchanged <label> <playbook> [args...]: must succeed with changed=0.
expect_unchanged() {
  local label="$1"; shift
  expect_ok "$label" "$@"
  grep -Eq 'changed=0 ' "$logdir/$label.log" || { cat "$logdir/$label.log"; fail "$label: not idempotent"; }
}

# expect_refused <label> <message> <playbook> [args...]: must fail with <message>.
expect_refused() {
  local label="$1" message="$2"; shift 2
  if run_playbook "$@" >"$logdir/$label.log" 2>&1; then
    fail "$label: playbook accepted input it should have refused"
  fi
  grep -q "$message" "$logdir/$label.log" || { cat "$logdir/$label.log"; fail "$label: wrong failure reason"; }
}

echo "== starting container ($IMAGE)"
docker run -d --name "$NAME" --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "${mount_src}:/repo:ro" "$IMAGE" >/dev/null

# systemd needs a moment before `systemctl` works.
for _ in $(seq 1 20); do
  docker exec "$NAME" systemctl is-system-running --wait >/dev/null 2>&1 && break
  sleep 1
done

echo "== preparing the guest"
docker exec "$NAME" bash -euc "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq openssh-server python3-pip python3-debian ca-certificates sudo >/dev/null
  id ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
  ssh-keygen -A >/dev/null
  # What cloud-init leaves behind: a drop-in that re-enables passwords.
  printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/50-cloud-init.conf
  systemctl enable --now ssh >/dev/null 2>&1 || systemctl start ssh
  pip install --break-system-packages -q 'ansible-core==${ANSIBLE_CORE_VERSION}'
  printf '[homelab_vms]\nlocalhost ansible_connection=local ansible_user=ubuntu\n[vpn_gateway]\nlocalhost ansible_connection=local ansible_user=ubuntu\n[k8s_control_plane]\nlocalhost ansible_connection=local ansible_user=ubuntu\n' > /tmp/inv.ini
"

# --------------------------------------------------------------- tofu_inventory
echo "== tofu_inventory"
inventory_json='{
  "vpn01":    {"role": "vpn",           "vm_id": 101, "ip_address": "10.0.0.11/24"},
  "cp01":     {"role": "control-plane", "vm_id": 102, "ip_address": "10.0.0.12/24"},
  "worker01": {"role": "worker",        "vm_id": 103, "ip_address": "10.0.0.13/24"},
  "worker03": {"role": "worker",        "vm_id": 105, "ip_address": "10.0.0.15/24"}
}'
inv="/repo/ansible/inventories/production/tofu_inventory.py"
inv_out="$(docker exec -e TOFU_NODES_JSON="$inventory_json" "$NAME" python3 "$inv" --list)" \
  || fail "tofu_inventory: --list failed"
echo "$inv_out" | docker exec -i "$NAME" python3 -c '
import json, sys
inv = json.load(sys.stdin)
hv = inv["_meta"]["hostvars"]
assert inv["k8s_workers"]["hosts"] == ["worker01", "worker03"], inv["k8s_workers"]
assert inv["k8s_control_plane"]["hosts"] == ["cp01"]
assert inv["vpn_gateway"]["hosts"] == ["vpn01"]
assert inv["k8s_nodes"]["hosts"] == ["cp01", "worker01", "worker03"]
assert sorted(inv["homelab_vms"]["hosts"]) == ["cp01", "vpn01", "worker01", "worker03"]
assert hv["worker03"] == {"ansible_host": "10.0.0.15", "ansible_user": "ubuntu", "vmid": 105, "node_role": "worker"}, hv["worker03"]
' || fail "tofu_inventory: groups or host variables are wrong (a new worker must appear with no other edit)"
if docker exec -e TOFU_NODES_JSON='{"x": {"role": "gpu", "vm_id": 1, "ip_address": "10.0.0.1/24"}}' "$NAME" python3 "$inv" --list >/dev/null 2>&1; then
  fail "tofu_inventory: accepted a node with an unknown role"
fi

# ------------------------------------------------------- proxmox_vm_startup, proxmox_backup
# Two standalone Proxmox nodes: each host acts only on the VMs OpenTofu says are on it.
# `qm`, `pvesh` and `pvesm` are stand-ins that log their calls (there is no Proxmox here);
# both "hosts" are this container, told apart by STUB_HOST.
echo "== proxmox_vm_startup / proxmox_backup on two Proxmox hosts"
docker exec "$NAME" bash -euc '
  mkdir -p /tmp/mh/bin
  printf "#!/bin/sh\necho \"\$STUB_HOST qm \$*\" >> \"\$STUB_LOG\"\nexit 0\n" > /tmp/mh/bin/qm
  printf "#!/bin/sh\necho \"\$STUB_HOST pvesm \$*\" >> \"\$STUB_LOG\"\necho \"Name Type Status\"\necho \"local dir active\"\n" > /tmp/mh/bin/pvesm
  cat > /tmp/mh/bin/pvesh <<"STUB"
#!/bin/sh
echo "$STUB_HOST pvesh $*" >> "$STUB_LOG"
case "$STUB_HOST $1 $2" in
  "pve01 get /cluster/resources") echo "[{\"vmid\":101},{\"vmid\":102},{\"vmid\":103},{\"vmid\":9000}]" ;;
  "pve02 get /cluster/resources") echo "[{\"vmid\":104},{\"vmid\":9000}]" ;;
  *"get /cluster/backup") echo "[]" ;;
esac
STUB
  chmod +x /tmp/mh/bin/*
  printf "[proxmox]\npve01 ansible_connection=local\npve02 ansible_connection=local\n" > /tmp/mh/inv.ini
  cat > /tmp/mh/play.yml <<"PLAY"
- hosts: proxmox
  gather_facts: false
  environment:
    PATH: "/tmp/mh/bin:{{ lookup(\"env\", \"PATH\") }}"
    STUB_HOST: "{{ inventory_hostname }}"
    STUB_LOG: /tmp/mh/calls.log
  roles:
    - proxmox_vm_startup
    - proxmox_backup
PLAY
'
multi_host_nodes='{
  "vpn01":    {"role": "vpn",           "proxmox_host": "pve01", "vm_id": 101, "ip_address": "10.0.0.11/24"},
  "cp01":     {"role": "control-plane", "proxmox_host": "pve01", "vm_id": 102, "ip_address": "10.0.0.12/24"},
  "worker01": {"role": "worker",        "proxmox_host": "pve01", "vm_id": 103, "ip_address": "10.0.0.13/24"},
  "worker02": {"role": "worker",        "proxmox_host": "pve02", "vm_id": 104, "ip_address": "10.0.0.14/24"}
}'
docker exec -e TOFU_NODES_JSON="$multi_host_nodes" -e ANSIBLE_CONFIG=/repo/ansible/ansible.cfg \
  -e ANSIBLE_LOCAL_TEMP=/tmp/.ansible -e ANSIBLE_NOCOLOR=1 -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
  -e ANSIBLE_ROLES_PATH=/repo/ansible/roles "$NAME" \
  ansible-playbook -i /tmp/mh/inv.ini -i "$inv" /tmp/mh/play.yml >"$logdir/multihost.log" 2>&1 \
  || { cat "$logdir/multihost.log"; fail "proxmox roles on two hosts: playbook failed"; }
docker exec -e TOFU_NODES_JSON="$multi_host_nodes" "$NAME" python3 "$inv" --list | docker exec -i "$NAME" python3 -c '
import json, sys
hv = json.load(sys.stdin)["_meta"]["hostvars"]
assert hv["worker02"]["proxmox_host"] == "pve02" and hv["cp01"]["proxmox_host"] == "pve01", hv
' || fail "tofu_inventory: proxmox_host is missing or wrong"
mh_calls="$(docker exec "$NAME" cat /tmp/mh/calls.log)"
echo "$mh_calls" | grep -q '^pve02 qm set 104 --startup order=3$' || fail "proxmox_vm_startup: pve02 did not order its own worker (VM 104)"
echo "$mh_calls" | grep -q '^pve01 qm set 102 --startup order=2,up=60$' || fail "proxmox_vm_startup: pve01 did not order cp01"
if echo "$mh_calls" | grep -qE '^pve02 qm (config|set) 10[123]'; then fail "proxmox_vm_startup: pve02 touched a VM that is on pve01"; fi
if echo "$mh_calls" | grep -qE '^pve01 qm (config|set) 104'; then fail "proxmox_vm_startup: pve01 touched a VM that is on pve02"; fi
echo "$mh_calls" | grep -q '^pve01 pvesh create /cluster/backup' || fail "proxmox_backup: pve01, which holds cp01, has no backup job"
if echo "$mh_calls" | grep -qE '^pve02 pvesh create /cluster/backup'; then fail "proxmox_backup: pve02 got a backup job for a VM it does not have"; fi

# The temporary OpenTofu session (tofu_session_open / tofu_session_close): a token per Proxmox
# host in a private directory while it lasts, gone when it ends. Same stand-ins as above.
echo "== proxmox_bootstrap: temporary OpenTofu session"
docker exec "$NAME" bash -euc '
  cat > /tmp/mh/bin/pveum <<"STUB"
#!/bin/sh
echo "$STUB_HOST pveum $*" >> "$STUB_LOG"
case "$1 $2" in
  "user list" | "acl list" | "role list") echo "[]" ;;
  "user token") [ "$3" = add ] && echo "{\"value\":\"00000000-0000-4000-8000-000000000001\"}" ;;
esac
exit 0
STUB
  chmod +x /tmp/mh/bin/pveum
  # the pool step reads these two
  sed -i "s#^esac#  \"pve01 get /pools\"|\"pve02 get /pools\") echo \"[{\\\\\"poolid\\\\\":\\\\\"homelab\\\\\"}]\" ;;\n  \"pve01 get /pools/homelab\"|\"pve02 get /pools/homelab\") echo \"{\\\\\"members\\\\\":[]}\" ;;\nesac#" /tmp/mh/bin/pvesh
  sed -i "s/^    - proxmox_vm_startup/    - proxmox_bootstrap/; /^    - proxmox_backup/d" /tmp/mh/play.yml
'
session_run() {
  docker exec -e TOFU_NODES_JSON="$multi_host_nodes" -e ANSIBLE_CONFIG=/repo/ansible/ansible.cfg \
    -e ANSIBLE_LOCAL_TEMP=/tmp/.ansible -e ANSIBLE_NOCOLOR=1 -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
    -e ANSIBLE_ROLES_PATH=/repo/ansible/roles "$NAME" \
    ansible-playbook -i /tmp/mh/inv.ini /tmp/mh/play.yml --tags "$1" \
    -e proxmox_bootstrap_ca_dir=/tmp/mh/cfg -e proxmox_bootstrap_expected_mgmt_cidr=10.0.0.0/24
}
session_run tofu_session_open >"$logdir/session-open.log" 2>&1 \
  || { cat "$logdir/session-open.log"; fail "tofu_session_open failed"; }
[ "$(docker exec "$NAME" stat -c %a /tmp/mh/cfg/session/pve01.token)" = 600 ] || fail "the session token of pve01 is not private (mode 600)"
docker exec "$NAME" test -s /tmp/mh/cfg/session/pve02.token || fail "no session token was saved for pve02"
docker exec "$NAME" grep -q '^tofu-session@pve!session=' /tmp/mh/cfg/session/pve01.token || fail "the session token is not in user@realm!id=secret form"
if grep -q '00000000-0000-4000' "$logdir/session-open.log"; then fail "the session secret was printed in the Ansible output"; fi
session_run tofu_session_close >"$logdir/session-close.log" 2>&1 \
  || { cat "$logdir/session-close.log"; fail "tofu_session_close failed"; }
if docker exec "$NAME" bash -c 'ls /tmp/mh/cfg/session/*.token' >/dev/null 2>&1; then fail "the session token files were not removed"; fi
docker exec "$NAME" grep -q '^pve02 pveum user delete tofu-session@pve' /tmp/mh/calls.log || fail "the session user was not removed from pve02"


# ------------------------------------------------------------ worker.sh / proxmox-node.sh helper
# The one-line entries of terraform.tfvars and the Proxmox hosts of the inventory are edited by
# scripts/lib/homelab_config.py, so nobody edits HCL or YAML by hand to add a worker or a node.
echo "== homelab_config.py (workers, nodes, hosts)"
docker exec -i "$NAME" bash -euc '
  cd /tmp && mkdir -p cfgtest && cd cfgtest
  cat > tv <<"TV"
proxmox_node_name = "pve01"
vpn01_ip = "10.0.0.11/24"
cp01_ip = "10.0.0.12/24"

workers = {
  worker01 = { vmid = 103, ip_address = "10.0.0.13/24" }
}
TV
  printf "proxmox:\n  hosts:\n    pve01:\n      ansible_host: 10.0.0.2\n      ansible_user: root\n" > hosts.yml
  export HOMELAB_TFVARS=/tmp/cfgtest/tv HOMELAB_INVENTORY=/tmp/cfgtest/hosts.yml HOMELAB_CONFIG_DIR=/tmp/cfgtest/cfg
  c="python3 /repo/scripts/lib/homelab_config.py"
  $c nodes add pve02 https://10.0.0.20:8006/ >/dev/null; grep -qx "  pve02 = { endpoint = \"https://10.0.0.20:8006/\", slot = 1 }" tv
  $c nodes add pve03 https://10.0.0.30:8006/ >/dev/null; grep -q "pve03 = { endpoint = \"https://10.0.0.30:8006/\", slot = 2 }" tv
  $c workers add worker02 --node pve02 --memory 5632 --cores 3 >/dev/null
  $c workers add worker03 >/dev/null
  grep -qx "  worker02 = { vmid = 104, ip_address = \"10.0.0.14/24\", node = \"pve02\", cores = 3, memory = 5632 }" tv
  grep -qx "  worker03 = { vmid = 105, ip_address = \"10.0.0.15/24\" }" tv
  $c workers set-node worker03 pve02 >/dev/null; grep -q "worker03 = { vmid = 105, ip_address = \"10.0.0.15/24\", node = \"pve02\" }" tv
  $c workers remove worker03 >/dev/null; ! grep -q worker03 tv
  ! $c workers add worker02 2>/dev/null   # a name is used once
  ! $c workers add worker07 --node nowhere 2>/dev/null   # a node the lab does not know
  ! $c nodes add pve02 https://x/ 2>/dev/null
  $c hosts add pve02 10.0.0.20 >/dev/null
  python3 -c "
import yaml; h = list(yaml.safe_load(open(\"hosts.yml\"))[\"proxmox\"][\"hosts\"]); assert h == [\"pve01\", \"pve02\"], h"
  grep -q "^vpn01_ip" tv && grep -q "^proxmox_node_name" tv   # what it does not manage stays
' || fail "homelab_config.py: adding and removing workers, nodes and hosts is wrong"


# ---------------------------------------------------------------- guest_hardening
echo "== guest_hardening"
before="$(docker exec "$NAME" sshd -T | grep -E '^passwordauthentication ')"
[ "$before" = "passwordauthentication yes" ] \
  || fail "precondition: expected the cloud-init drop-in to enable passwords, got '$before'"

expect_ok        gh-run1 guest-hardening.yml
expect_unchanged gh-run2 guest-hardening.yml

effective="$(docker exec "$NAME" sshd -T)"
for expected in \
  "passwordauthentication no" \
  "kbdinteractiveauthentication no" \
  "permitrootlogin no" \
  "pubkeyauthentication yes" \
  "x11forwarding no" \
  "maxauthtries 3" \
  "allowusers ubuntu"; do
  echo "$effective" | grep -qxF "$expected" || fail "guest_hardening: missing in effective sshd config: $expected"
done

expect_refused gh-lockout "does not include the connecting account" \
  guest-hardening.yml -e '{"guest_hardening_ssh_allow_users":["someoneelse"]}'

# --------------------------------------------------------------------- tailscale
echo "== tailscale"
ts_vars=(-e tailscale_join=false -e '{"tailscale_advertise_routes":["203.0.113.10/32"]}')

expect_ok        ts-run1 tailscale.yml "${ts_vars[@]}"
expect_unchanged ts-run2 tailscale.yml "${ts_vars[@]}"

docker exec "$NAME" dpkg -s tailscale 2>/dev/null | grep -q '^Status: install ok installed' \
  || fail "tailscale: package not installed"
docker exec "$NAME" grep -q 'pkgs.tailscale.com/stable/ubuntu' /etc/apt/sources.list.d/tailscale.sources \
  || fail "tailscale: apt source missing"
docker exec "$NAME" grep -qi '^Signed-By:' /etc/apt/sources.list.d/tailscale.sources \
  || fail "tailscale: apt source is not signed"
[ "$(docker exec "$NAME" sysctl -n net.ipv4.ip_forward)" = "1" ] \
  || fail "tailscale: IPv4 forwarding is not enabled"
docker exec "$NAME" systemctl is-active --quiet tailscaled \
  || fail "tailscale: tailscaled is not running"

expect_refused ts-noroutes "tailscale_advertise_routes is empty" \
  tailscale.yml -e tailscale_join=false -e '{"tailscale_advertise_routes":[]}'

# -------------------------------------------------------------------- etcd_backup
echo "== etcd_backup"
etcd_vars=(-e etcd_backup_install_binaries=false -e etcd_backup_keep=3)

expect_ok        etcd-run1 etcd-backup.yml "${etcd_vars[@]}"
expect_unchanged etcd-run2 etcd-backup.yml "${etcd_vars[@]}"

docker exec "$NAME" systemd-analyze verify /etc/systemd/system/etcd-snapshot.service /etc/systemd/system/etcd-snapshot.timer \
  || fail "etcd_backup: systemd units do not verify"
docker exec "$NAME" systemctl is-enabled --quiet etcd-snapshot.timer || fail "etcd_backup: timer not enabled"
docker exec "$NAME" systemctl is-active --quiet etcd-snapshot.timer || fail "etcd_backup: timer not active"

# Stand-ins for etcdctl/etcdutl and the PKI, so the script's own logic runs for real.
docker exec "$NAME" bash -euc '
  mkdir -p /tmp/bk/pki/etcd /tmp/bk/enc
  echo "encryption-config" > /tmp/bk/enc/encryption-config.yaml
  for f in ca.crt healthcheck-client.crt healthcheck-client.key; do echo x > /tmp/bk/pki/etcd/$f; done
  printf "#!/bin/sh\nfor a; do last=\$a; done\necho fake-snapshot > \"\$last\"\n" > /tmp/bk/etcdctl
  printf "#!/bin/sh\nexit 0\n" > /tmp/bk/etcdutl
  chmod +x /tmp/bk/etcdctl /tmp/bk/etcdutl
'
snapshot_env=(-e BACKUP_DIR=/tmp/bk/out -e KEEP=3 -e ETCDCTL=/tmp/bk/etcdctl -e PKI_DIR=/tmp/bk/pki -e ENC_DIR=/tmp/bk/enc)
for _ in 1 2 3 4 5; do
  docker exec "${snapshot_env[@]}" -e ETCDUTL=/tmp/bk/etcdutl "$NAME" /usr/local/sbin/etcd-snapshot >/dev/null \
    || fail "etcd_backup: snapshot script failed"
  sleep 1.1 # file names carry a one-second timestamp
done
[ "$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/etcd-*.db | wc -l')" = "3" ] \
  || fail "etcd_backup: retention did not keep exactly 3 snapshots"
[ "$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/pki-*.tar.gz | wc -l')" = "3" ] \
  || fail "etcd_backup: retention did not keep exactly 3 PKI archives"
docker exec "$NAME" bash -c 'tar tzf "$(ls -1t /tmp/bk/out/pki-*.tar.gz | head -1)"' | grep -q '^enc/encryption-config.yaml$'   || fail "etcd_backup: the archive does not contain the Secret-encryption key"
[ "$(docker exec "$NAME" stat -c %a "$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/etcd-*.db | tail -1')")" = "600" ] \
  || fail "etcd_backup: snapshot is not private (mode 600)"

newest_before="$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/etcd-*.db | tail -1')"
if docker exec "${snapshot_env[@]}" -e ETCDUTL=/bin/false "$NAME" /usr/local/sbin/etcd-snapshot >/dev/null 2>&1; then
  fail "etcd_backup: a snapshot that fails verification was accepted"
fi
[ "$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/etcd-*.db | tail -1')" = "$newest_before" ] \
  || fail "etcd_backup: a failed verification still produced a snapshot file"
[ "$(docker exec "$NAME" bash -c 'ls /tmp/bk/out/*.partial 2>/dev/null | wc -l')" = "0" ] \
  || fail "etcd_backup: a partial file was left behind"

# --------------------------------------------------------------- kubelet_server_tls
echo "== kubelet_server_tls"
# A kubelet configuration as kubeadm writes it (without the setting), a stand-in kubelet service
# that systemd really restarts, and a stand-in for kubectl that records what the role asks of
# the cluster: the ConfigMap (a file) starts without the setting, `get` prints it and `patch`
# logs the patch and adds the setting.
docker exec "$NAME" bash -euc '
  mkdir -p /var/lib/kubelet
  printf "apiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\nrotateCertificates: true\nruntimeRequestTimeout: 0s\n" > /var/lib/kubelet/config.yaml
  chmod 600 /var/lib/kubelet/config.yaml
  printf "[Unit]\nDescription=stand-in kubelet\n[Service]\nExecStart=/bin/sleep infinity\n" > /etc/systemd/system/kubelet.service
  systemctl daemon-reload
  systemctl start kubelet
  printf "rotateCertificates: true\n" > /tmp/kubelet-cm
  : > /tmp/kubectl-patches
  cat > /usr/local/bin/kubectl <<"STUB"
#!/bin/sh
case " $* " in
  *" patch "*)
    printf "%s\n" "$*" >> /tmp/kubectl-patches
    printf "serverTLSBootstrap: true\n" >> /tmp/kubelet-cm ;;
  *) cat /tmp/kubelet-cm ;;
esac
STUB
  chmod +x /usr/local/bin/kubectl
  printf "%s\n" "- hosts: localhost" "  gather_facts: false" "  roles: [kubelet_server_tls]" > /tmp/kst.yml
'
run_kst() {
  docker exec -e ANSIBLE_CONFIG=/repo/ansible/ansible.cfg -e ANSIBLE_LOCAL_TEMP=/tmp/.ansible \
    -e ANSIBLE_NOCOLOR=1 -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
    "$NAME" ansible-playbook -i /tmp/inv.ini /tmp/kst.yml
}
pid_before="$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)"
run_kst >"$logdir/kst-run1.log" 2>&1 || { cat "$logdir/kst-run1.log"; fail "kubelet_server_tls: first run failed"; }
[ "$(docker exec "$NAME" grep -c '^serverTLSBootstrap: true$' /var/lib/kubelet/config.yaml)" = "1" ] \
  || fail "kubelet_server_tls: the kubelet configuration does not have the setting exactly once"
[ "$(docker exec "$NAME" stat -c %a /var/lib/kubelet/config.yaml)" = "600" ] \
  || fail "kubelet_server_tls: the kubelet configuration lost its root-only mode"
[ "$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)" != "$pid_before" ] \
  || fail "kubelet_server_tls: the kubelet was not restarted after the change"
[ "$(docker exec "$NAME" bash -c 'wc -l < /tmp/kubectl-patches')" = "1" ] \
  || fail "kubelet_server_tls: the ConfigMap was not patched exactly once"
docker exec "$NAME" grep -q -e 'patch configmap kubelet-config' /tmp/kubectl-patches \
  || fail "kubelet_server_tls: the patch does not target the kubelet-config ConfigMap"
# The patch keeps what was in the ConfigMap and adds the setting, nothing else.
docker exec "$NAME" grep -q -e '"kubelet": *"rotateCertificates: true\\nserverTLSBootstrap: true\\n"' /tmp/kubectl-patches \
  || fail "kubelet_server_tls: the patch does not keep the current content and add the setting"
pid_after="$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)"
run_kst >"$logdir/kst-run2.log" 2>&1 || { cat "$logdir/kst-run2.log"; fail "kubelet_server_tls: second run failed"; }
grep -Eq 'changed=0 ' "$logdir/kst-run2.log" || { cat "$logdir/kst-run2.log"; fail "kubelet_server_tls: not idempotent"; }
[ "$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)" = "$pid_after" ] \
  || fail "kubelet_server_tls: an idempotent run restarted the kubelet"
[ "$(docker exec "$NAME" bash -c 'wc -l < /tmp/kubectl-patches')" = "1" ] \
  || fail "kubelet_server_tls: the ConfigMap was patched again although it already had the setting"

echo "PASS: guest_hardening, tailscale, etcd_backup and kubelet_server_tls converge, are idempotent and refuse bad input"
