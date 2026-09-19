# 0003. Upstream Kubernetes (kubeadm) over k3s/managed distros

Status: Accepted
Date: 2026-09-15

## Context

The project's explicit learning objective is understanding Kubernetes
internals — control-plane components, etcd, PKI/certificate lifecycle,
kubelet/containerd interaction — not just running workloads on top of it.
Simplified distributions (k3s, k0s, minikube, kind) trade away exactly that
visibility in exchange for convenience.

## Decision

Bootstrap the cluster with upstream Kubernetes using `kubeadm` on
containerd, not a simplified or managed distribution.

## Alternatives considered

- **k3s** — lower resource footprint (relevant given the 16 GB ceiling) and
  faster to stand up, but bundles/replaces components (e.g. its own CNI
  defaults, embedded etcd options) in ways that reduce exposure to the
  exact mechanics this project exists to teach.
- **kind/minikube** — designed for local dev/CI, not for practicing
  node-level operations, VM lifecycle, or realistic failure scenarios like
  "a worker VM goes down."
- **A managed cloud Kubernetes service** — removes the infrastructure and
  bootstrap learning entirely, and reintroduces recurring cost.

## Consequences

More manual bootstrap work and a heavier resource footprint than k3s under
the same 16 GB ceiling — mitigated by the conservative sizing in
[`../architecture/infrastructure.md`](../architecture/infrastructure.md#compute-and-memory-allocation).
In exchange, `kubeadm`, PKI, and etcd operations are direct, first-hand
experience rather than abstracted away.
