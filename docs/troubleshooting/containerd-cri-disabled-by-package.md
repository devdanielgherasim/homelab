# `kubeadm init` fails: unknown service runtime.v1.RuntimeService

## Symptom

`kubeadm init` on `cp01` failed its preflight checks:

```text
[ERROR CRI]: ... unknown service runtime.v1.RuntimeService
```

The `kubeadm_prereqs` role had reported success on all three nodes.

## Diagnosis

Checked containerd's config directly over SSH on all three nodes instead of
re-running the playbook. `/etc/containerd/config.toml` existed and contained
`disabled_plugins = ["cri"]`, identical on every node.

## Root cause

The `containerd.io` package from Docker's apt repository ships a default
`config.toml` with the CRI plugin disabled. The role's "generate default
config if missing" task uses `creates: /etc/containerd/config.toml`, so it
was silently skipped: the package had already created the file. containerd
therefore never exposed the CRI gRPC service that kubelet and kubeadm need.

## Fix

Added an idempotent task in `ansible/roles/kubeadm_prereqs/tasks/containerd.yml`
that removes the `disabled_plugins =` line (`lineinfile` with
`state: absent`) and notifies the existing `Restart containerd` handler. The
re-run finished with `0 failed` on all nodes.

## Prevention

- The task comment records the exact package behaviour, confirmed on live
  nodes, so nobody has to rediscover it.
- Lesson: a `creates:`-guarded generate step is not a safe way to assert
  desired config when a package may pre-create the file. Follow-up: manage
  the whole `config.toml` from a template or drop-in so the desired state is
  fully declared. `kubeadm` preflight did its job here; it caught the
  problem before any cluster state was written.
