# 0018. Kubelet serving certificates from the cluster CA, and metrics-server that verifies them

Status: Proposed
Date: 2026-09-20

## Context

metrics-server (`kubectl top`, the horizontal pod autoscaler, and the scaling work on the
roadmap) has to read the kubelets' metrics endpoints over TLS. The kubelets here serve with
**self-signed** certificates (`CN=worker01-ca@...`, one DNS name and no IP), because kubeadm
does not turn on `serverTLSBootstrap` by itself. The usual shortcut, `--kubelet-insecure-tls`,
switches certificate verification off; this repository does not do that. Prometheus scrapes the
kubelets the same way today, with `insecureSkipVerify: true` (the chart default), and CIS 1.2.5
(`--kubelet-certificate-authority`) has been an accepted failure for the same reason
(ADR-0013, "deferred until the platform is managed through GitOps", which it now is).

## Decision

1. Make the kubelets request their serving certificate from the cluster CA
   (`serverTLSBootstrap: true`). New clusters get it from a `KubeletConfiguration` document in
   `kubeadm-config` (roles/kubeadm_init), which `kubeadm init` uploads to the `kubelet-config`
   ConfigMap that joining nodes read. Existing nodes get it from the role `kubelet_server_tls`
   (`playbooks/k8s-kubelet-tls.yml`), one node at a time.
2. Approve the certificate requests with **kubelet-csr-approver** (PostFinance), installed by
   Argo CD. Kubernetes never approves `kubernetes.io/kubelet-serving` requests by itself. The
   approver accepts a request only from the node's own identity, for a name that matches
   `providerRegex`, with one DNS name and a bounded lifetime, and it handles the yearly renewals.
3. Install **metrics-server** by Argo CD with `--kubelet-certificate-authority` pointing at the
   cluster CA, and with the chart's generated certificate for its own APIService (verified, not
   `insecureSkipTLSVerify`). The generated certificate differs at every render, so the
   Application ignores that Secret and the APIService's `caBundle`, as istiod's webhooks are.
4. After the nodes have the new certificates, switch off `insecureSkipVerify` in Prometheus's
   kubelet monitor.

## Alternatives considered

- **`--kubelet-insecure-tls` for metrics-server.** Fastest, and against the rule that
  verification is never switched off. It would also leave Prometheus and CIS 1.2.5 as they are.
- **Approving the requests by hand** (`kubectl certificate approve`). A manual step after every
  node join and every yearly renewal, which the bootstrap requirement rules out.
- **A small CronJob that approves whatever is pending.** Less to install, but it is the
  approval logic of a security control written from scratch; the maintained controller already
  checks identity, name and lifetime.
- **cert-manager for the metrics-server certificate.** Removes the need to ignore generated
  data, but adds a component only for this.

## Consequences

Kubelet-to-client traffic is verified; metrics-server, `kubectl top` and, later, autoscaling
work without a disabled check, and the accepted CIS 1.2.5 failure can be closed by adding
`--kubelet-certificate-authority` to the API server (a separate change, because it restarts the
API server). Costs: two small components (about 16 MiB and 40 MiB of requests), and one more
thing that has to be right during a rebuild: the kubelets ask for their certificates as soon as
they start, and the approver only exists once Argo CD has installed it, so on a cluster built
from zero the requests wait (the kubelet keeps its self-signed certificate meanwhile) and
metrics-server reports no metrics until they are approved.

Known limits: `providerIpPrefixes` is not set, because the real node network stays out of the
repository, so the IP addresses in a request are not checked against a range (the requester is
still authenticated as that node). `bypassDnsResolution` is on, because node names are not in DNS.
Metrics-server 0.9.0 and the approver 1.2.15 are not documented as tested on Kubernetes 1.37,
like Cilium, Argo CD and Istio (see `STATUS.md`).
