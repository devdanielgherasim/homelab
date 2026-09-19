#!/usr/bin/env bash
# Converge tests for the Ansible roles that can be exercised without real hosts.
#
# Roles are applied inside one throwaway systemd container (never against real
# infrastructure) and each is checked for the same three properties: it reaches
# the intended state, a second run changes nothing (idempotence), and its safety
# checks refuse bad input.
#
#   guest_hardening  beats a cloud-init drop-in, is idempotent, refuses a lock-out.
#   tailscale        installs from the signed repo, enables forwarding, is idempotent,
#                    refuses to run without routes. It never joins a tailnet here.
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
  printf '[homelab_vms]\nlocalhost ansible_connection=local ansible_user=ubuntu\n[vpn_gateway]\nlocalhost ansible_connection=local ansible_user=ubuntu\n' > /tmp/inv.ini
"

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

echo "PASS: guest_hardening and tailscale converge, are idempotent and refuse bad input"
