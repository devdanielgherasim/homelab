# CIS Kubernetes Benchmark

Measured with [kube-bench](https://github.com/aquasecurity/kube-bench) 0.16.0
against the control-plane node, benchmark `cis-1.12` (chosen explicitly: the
tool cannot auto-detect Kubernetes 1.37). The choices behind the changes are in
[ADR-0013](../adr/0013-control-plane-hardening.md).

## Result

| | Pass | Fail | Warn (manual) |
|---|---|---|---|
| Before hardening (2026-09-19) | 62 | 13 | 56 |
| After hardening (2026-09-19) | 76 | 2 | 53 |

Warn means the benchmark cannot decide automatically and asks a person to
verify. Those items are not counted as passes here.

## What changed

| Checks | Finding | Fix |
|---|---|---|
| 1.2.15, 1.3.2, 1.4.1 | `--profiling` not disabled | `profiling=false` on the API server, controller manager and scheduler |
| 1.2.16 - 1.2.19 | No audit log | Audit policy and log flags on the API server |
| 1.2.30 | Service account token expiry extended | `service-account-extend-token-expiration=false` |
| 1.1.12 | etcd data not owned by an `etcd` user | Dedicated `etcd` account owns `/var/lib/etcd` |
| 4.1.1, 4.1.9 | kubelet service file and config readable by all | Mode 600 on the control plane and both workers |

Beyond what the benchmark measures: Secrets are encrypted at rest (all seven
were confirmed stored with the `k8s:enc:secretbox` prefix by reading them
directly from etcd), Pod Security admission enforces `baseline` (a privileged
pod is refused in `default` and accepted in the exempt `kube-system`, checked
with a server-side dry run), and audit records contain no Secret bodies.

## Accepted failures

- **1.2.5** `--kubelet-certificate-authority`: the kubelets now serve certificates from the
  cluster CA (ADR-0018, 2026-09-20), which was the missing prerequisite; what is left is to add
  the flag to the API server, a separate change that restarts it. Originally: needs `serverTLSBootstrapping`
  and a certificate-request approver. Deferred until GitOps; see ADR-0013.
- **4.3.1** kube-proxy metrics bind address: kube-proxy is not installed
  (Cilium replaces it).

## Reproduce

Download the pinned release and check it before running it (the checksum is the
one published in the release's `checksums.txt`):

```bash
V=0.16.0
curl -sSfLO "https://github.com/aquasecurity/kube-bench/releases/download/v${V}/kube-bench_${V}_linux_amd64.tar.gz"
echo "82dbc7e598740dc9344d41f8ad0b8210d57c4c00bdb2c5f1d8a69a2b98baddcf  kube-bench_${V}_linux_amd64.tar.gz" | sha256sum --check
tar xzf "kube-bench_${V}_linux_amd64.tar.gz"
sudo ./kube-bench run --benchmark cis-1.12 --config-dir ./cfg --config ./cfg/config.yaml
```

Run it on the control-plane node. The worker-node checks (section 4) also apply
to the workers.
