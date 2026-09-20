#!/usr/bin/env bash
# Converge tests for the Ansible roles that can be exercised without real hosts.
#
# Roles are applied inside one throwaway systemd container (never against real
# infrastructure) and each is checked for the same three properties: it reaches
# the intended state, a second run changes nothing (idempotence), and its safety
# checks refuse bad input.
#
#   tofu_inventory   builds the groups and host variables from OpenTofu's `nodes` output,
#                    shows a new worker with no other edit, rejects an unknown role.
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
# that systemd really restarts, and stand-ins for kubectl and kubeadm that record what the role
# asks of the cluster: the ConfigMap starts without the setting, and "kubeadm" adds it.
docker exec "$NAME" bash -euc '
  mkdir -p /var/lib/kubelet
  printf "apiVersion: kubelet.config.k8s.io/v1beta1\nkind: KubeletConfiguration\nrotateCertificates: true\nruntimeRequestTimeout: 0s\n" > /var/lib/kubelet/config.yaml
  chmod 600 /var/lib/kubelet/config.yaml
  printf "[Unit]\nDescription=stand-in kubelet\n[Service]\nExecStart=/bin/sleep infinity\n" > /etc/systemd/system/kubelet.service
  systemctl daemon-reload
  systemctl start kubelet
  printf "rotateCertificates: true\n" > /tmp/kubelet-cm
  : > /tmp/kubeadm-calls
  printf "#!/bin/sh\ncat /tmp/kubelet-cm\n" > /usr/local/bin/kubectl
  printf "#!/bin/sh\necho \"\$*\" >> /tmp/kubeadm-calls\nprintf \"serverTLSBootstrap: true\\\\n\" >> /tmp/kubelet-cm\n" > /usr/local/bin/kubeadm
  chmod +x /usr/local/bin/kubectl /usr/local/bin/kubeadm
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
[ "$(docker exec "$NAME" cat /tmp/kubeadm-calls)" = "init phase upload-config kubelet --config /etc/kubernetes/kubeadm-config.yaml" ] \
  || fail "kubelet_server_tls: the ConfigMap was not refreshed from the kubeadm configuration"
pid_after="$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)"
run_kst >"$logdir/kst-run2.log" 2>&1 || { cat "$logdir/kst-run2.log"; fail "kubelet_server_tls: second run failed"; }
grep -Eq 'changed=0 ' "$logdir/kst-run2.log" || { cat "$logdir/kst-run2.log"; fail "kubelet_server_tls: not idempotent"; }
[ "$(docker exec "$NAME" systemctl show -p MainPID --value kubelet)" = "$pid_after" ] \
  || fail "kubelet_server_tls: an idempotent run restarted the kubelet"
[ "$(docker exec "$NAME" wc -l < /tmp/kubeadm-calls)" = "1" ] \
  || fail "kubelet_server_tls: the ConfigMap was refreshed again although it already had the setting"

echo "PASS: guest_hardening, tailscale, etcd_backup and kubelet_server_tls converge, are idempotent and refuse bad input"
