#!/usr/bin/env bash
# Converge test for ansible/roles/guest_hardening.
#
# Applies the role inside a throwaway systemd container (never against real
# hosts) and checks three properties:
#   1. it beats the cloud-init drop-in that re-enables password login,
#   2. a second run changes nothing (idempotence),
#   3. it refuses an allow-list that would lock Ansible out.
#
# Needs Docker only. Runs the same way locally and in CI.
set -euo pipefail

# Pinned by digest: a moving tag would make this test non-reproducible.
IMAGE="${TEST_IMAGE:-jrei/systemd-ubuntu:24.04@sha256:936c599ab7fb6019ff05ff3845cd7536f991848f8040c51c745931d3a648f144}"
NAME="role-test-guest-hardening-$$"
ANSIBLE_CORE_VERSION="2.21.2" # keep in sync with mise.toml

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Git Bash on Windows needs the Windows form of the path for docker -v.
mount_src="$(cd "$repo_root" && (pwd -W 2>/dev/null || pwd))"
export MSYS_NO_PATHCONV=1

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

run_playbook() {
  docker exec \
    -e ANSIBLE_CONFIG=/repo/ansible/ansible.cfg \
    -e ANSIBLE_LOCAL_TEMP=/tmp/.ansible \
    -e ANSIBLE_NOCOLOR=1 -e LC_ALL=C.UTF-8 -e LANG=C.UTF-8 \
    "$NAME" ansible-playbook -i /tmp/inv.ini /repo/ansible/playbooks/guest-hardening.yml "$@"
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
  apt-get install -y -qq openssh-server python3-pip sudo >/dev/null
  id ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
  ssh-keygen -A >/dev/null
  # What cloud-init leaves behind: a drop-in that re-enables passwords.
  printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/50-cloud-init.conf
  systemctl enable --now ssh >/dev/null 2>&1 || systemctl start ssh
  pip install --break-system-packages -q 'ansible-core==${ANSIBLE_CORE_VERSION}'
  printf '[homelab_vms]\nlocalhost ansible_connection=local ansible_user=ubuntu\n' > /tmp/inv.ini
"

before="$(docker exec "$NAME" sshd -T | grep -E '^passwordauthentication ')"
[ "$before" = "passwordauthentication yes" ] \
  || fail "precondition: expected the cloud-init drop-in to enable passwords, got '$before'"

echo "== run 1: apply the role"
run_playbook >/tmp/role-run1.log 2>&1 || { cat /tmp/role-run1.log; fail "role failed on first run"; }

echo "== run 2: must change nothing"
run_playbook >/tmp/role-run2.log 2>&1 || { cat /tmp/role-run2.log; fail "role failed on second run"; }
grep -Eq 'changed=0 ' /tmp/role-run2.log || { cat /tmp/role-run2.log; fail "role is not idempotent"; }

echo "== effective sshd configuration"
effective="$(docker exec "$NAME" sshd -T)"
for expected in \
  "passwordauthentication no" \
  "kbdinteractiveauthentication no" \
  "permitrootlogin no" \
  "pubkeyauthentication yes" \
  "x11forwarding no" \
  "maxauthtries 3" \
  "allowusers ubuntu"; do
  echo "$effective" | grep -qxF "$expected" || fail "missing in effective sshd config: $expected"
done

echo "== negative: allow-list that excludes the connecting account must be refused"
if run_playbook -e '{"guest_hardening_ssh_allow_users":["someoneelse"]}' >/tmp/role-run3.log 2>&1; then
  fail "role accepted an allow-list that would lock Ansible out"
fi
grep -q "does not include the connecting account" /tmp/role-run3.log || fail "wrong failure reason for the lock-out guard"

echo "PASS: guest_hardening converges, is idempotent and guards against lock-out"
