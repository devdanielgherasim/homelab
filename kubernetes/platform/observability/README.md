# Observability: metrics and dashboards

Prometheus, Grafana and the exporters that feed them, installed by Argo CD from the
`kube-prometheus-stack` Helm chart with a trimmed set of values. Logs (Loki) and traces (Tempo)
are deliberately not here yet; see [Deferred](#deferred).

| Path | What it is |
|---|---|
| `../apps/kube-prometheus-stack.yaml` | Argo `Application` installing the chart into the `monitoring` namespace (sync wave 10) |
| `../apps/observability-dashboards.yaml` | Argo `Application` for the plain manifests below (sync wave 11, after the stack has installed the CRDs) |
| `values.yaml` | Chart values, commented with the reason for each choice |
| `dashboards/` | Grafana dashboards as ConfigMaps (`grafana_dashboard: "1"`), loaded by the Grafana sidecar |
| `rules/capacity-rules.yaml` | `PrometheusRule`: capacity recording rules and two alerts |
| `monitors/cilium.yaml` | `PodMonitor`s for the Cilium agent, Hubble flow metrics and the Cilium operator |

## Components and versions

| Component | Version | Notes |
|---|---|---|
| kube-prometheus-stack chart | 91.4.1 (newest published on 2026-09-20) | Repository `https://prometheus-community.github.io/helm-charts` |
| Prometheus Operator | v0.94.0 | Chart appVersion |
| Prometheus | v3.14.0 (distroless) | Operator default for this chart |
| kube-state-metrics | v2.20.0 (subchart 8.5.0) | |
| node-exporter | v1.12.1 (subchart 4.57.0) | DaemonSet, one per node including the control plane |
| Grafana | 13.2.2 (subchart 13.2.5, from `grafana-community`) | Sidecars: kiwigrid/k8s-sidecar 2.11.2 |

The chart's subcharts are OCI dependencies, but they are packaged inside the chart tarball that
Argo downloads, so no extra chart repository or OCI registry has to be allowed in the AppProject.

## RAM budget

Only about 5 GiB of memory is free across the two workers for the whole platform. Requests
(what the scheduler reserves) of everything in this stack:

| Pod | Containers | CPU request | Memory request | Memory limit |
|---|---|---|---|---|
| Prometheus | prometheus 100m/300Mi, config-reloader 10m/16Mi | 110m | 316Mi | 732Mi |
| Prometheus Operator | 20m/48Mi | 20m | 48Mi | 128Mi |
| kube-state-metrics | 10m/48Mi | 10m | 48Mi | 128Mi |
| Grafana | grafana 50m/192Mi, two sidecars 10m/48Mi each | 70m | 288Mi | 640Mi |
| node-exporter (x3 nodes) | 10m/24Mi each | 30m | 72Mi | 192Mi |
| **Total** | | **240m** | **772Mi** | **1820Mi** |

Of the 772Mi, 24Mi is the control-plane node-exporter, so the load on the two workers is 748Mi of
requests. (The sidecars were first set to 32Mi/64Mi and were OOM-killed at start-up; Grafana itself
was first 128Mi/256Mi and measured 241Mi in use.) Measured working set after the first sync:
Prometheus 337Mi, Grafana pod about 410Mi (grafana 241, sidecars 88 and 79), everything else under
25Mi each. CPU limits are not set on purpose (throttling a metrics stack helps nobody). The
Prometheus memory limit (700Mi) is the one to watch: memory grows with the number of series. If it
is OOM-killed after Cilium and Istio start shipping ServiceMonitors, raise the limit first, then the
request.

The Prometheus data lives in an `emptyDir` (2Gi size limit, 1GiB `retentionSize`, 3 days
`retention`). There is no StorageClass, so the data is lost whenever the pod is rescheduled.

## Deliberately off, and why

- **Alertmanager.** No receiver worth waking up for yet. Alerts are still evaluated: see them on
  Prometheus's Alerts page or in Grafana. Turn it on in `values.yaml` when there is somewhere to send
  them.
- **Prometheus Operator admission webhooks and operator TLS.** The webhooks need a
  certificate-patch job or cert-manager. With the webhooks off, `prometheusOperator.tls.enabled`
  must be off too: verified with `helm template`, turning it on makes the operator mount a Secret
  (`kube-prometheus-stack-admission`) that nothing creates, so the pod would never start.
- **kube-controller-manager, kube-scheduler and etcd scraping, and their rule groups and
  dashboards.** kubeadm binds these to 127.0.0.1, so Prometheus cannot reach them. Leaving the
  targets on would only produce permanently `down` targets and firing alerts.
- **kube-proxy scraping and rules.** kube-proxy does not exist: Cilium replaces it
  (`kubeProxyReplacement=true`).
- **Windows, AIX and macOS dashboards and rules.** Linux only.
- **Persistence for Grafana and Prometheus.** No StorageClass. Grafana loses nothing: its
  dashboards and data sources are provisioned from Git.
- **Grafana sidecar access to Secrets and to other namespaces.** The chart default is a ClusterRole
  that reads every ConfigMap and Secret in the cluster. Here the sidecars use a namespaced Role and
  ConfigMaps only, which means every dashboard or data source ConfigMap must be created in the
  `monitoring` namespace (including Cilium's and Istio's, see [Deferred](#deferred)).
- **kube-state-metrics collectors for Secrets, ConfigMaps and 10 other kinds nothing uses**, for the
  same reason: less RBAC and less RAM.
- **Ingress or Gateway route.** The ClusterIP Services are reached by port-forward or Tailscale
  only, and Grafana requires a login (anonymous access is off). Put TLS and a real identity
  provider in front of it before exposing it through a route.
- **The 10-second scrape intervals.** kubelet, cAdvisor and the global scrape interval are 30s.

## Pod Security

The `monitoring` namespace is created and labelled by the platform stage
(`tofu/environments/platform/secrets.tf`): `enforce=privileged`, `audit=baseline`,
`warn=baseline`. node-exporter needs `hostNetwork`,
`hostPID` and `hostPath` volumes, which only `privileged` admits. Grafana, kube-state-metrics and
the operator pass the `restricted` profile. A `baseline` warning on node-exporter is expected;
anything else that warns is new and worth a look.

## The Grafana admin Secret

The credentials are not in Git and are not created by hand: the platform stage
(`tofu/environments/platform`, [ADR-0016](../../../docs/adr/0016-platform-bootstrap-with-opentofu.md))
generates the password and creates the `grafana-admin` Secret together with the namespace, before
Argo CD syncs this stack. If the Secret is missing the Grafana pod stays in
`CreateContainerConfigError`. To read the password:

```sh
cd tofu/environments/platform && tofu output -raw grafana_admin_password
```

Log in as `admin` with that password. Dashboards provisioned from Git are not editable in the UI
anyway; change them in Git.

## Reach Grafana and Prometheus

Neither is exposed outside the cluster. Forward them from a machine with cluster access (or over
Tailscale):

```sh
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Then open `http://localhost:3000` (Grafana, dashboard "Homelab / Capacity" in the "Homelab" folder)
and `http://localhost:9090` (Prometheus: Targets, Alerts, Rules pages).

## Capacity dashboard and rules

The "Homelab / Capacity" dashboard shows, per node and cluster-wide: memory and CPU requested against
allocatable, free allocatable memory, pending pods and unschedulable pods, plus where the requests
go by namespace. It is built only from kube-state-metrics series (`kube_node_status_allocatable`,
`kube_pod_container_resource_requests`, `kube_pod_status_phase`, `kube_pod_status_unschedulable`,
`kube_pod_info`), so it needs no control-plane scraping. "Requested" counts the requests of
`Pending` and `Running` pods placed on a node; `Succeeded` and `Failed` pods have released theirs.
Pods with no node yet (the `node` label is empty) are shown separately as demand without a node.

`rules/capacity-rules.yaml` records the per-node and cluster-wide requested/allocatable ratios
(`homelab:*_requests:ratio`) and defines two alerts:

- `ClusterMemoryRequestsHigh`: cluster memory requests above 80% of allocatable for 10 minutes.
- `PodsUnschedulable`: at least one unschedulable pod for 5 minutes.

The cluster-wide ratios include the control-plane node. Its memory is allocatable but tainted
against ordinary workloads, so the real headroom for workloads is the workers'; read the per-node
panels for that.

The chart's own default rules include `KubeMemoryOvercommit` and `KubeCPUOvercommit`, which assume
the cluster can lose its largest node. On a two-worker cluster that is tight, so expect them to fire
once the platform fills up. That is information, not a fault.

## Verify after the first sync (kubectl only)

```sh
# 1. Both Applications healthy and synced
kubectl -n argocd get applications kube-prometheus-stack observability-dashboards

# 2. Namespace labels and pods
kubectl get namespace monitoring --show-labels
kubectl -n monitoring get pods -o wide

# 3. CRDs, rule and dashboards present
kubectl get crd | grep monitoring.coreos.com
kubectl -n monitoring get prometheusrule homelab-capacity
kubectl -n monitoring get configmap -l grafana_dashboard=1

# 4. Prometheus targets: every "health" should be "up" (through the API server, no port-forward)
kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/targets?state=active" \
  | grep -o '"health":"[a-z]*"' | sort | uniq -c

# 5. The capacity rule groups were loaded by Prometheus (both should be listed; evaluation
#    errors show as health "err" on the Rules page)
kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/rules" \
  | grep -o '"name":"homelab-capacity[^"]*"'

# 6. Grafana is up (the health endpoint needs no login). That the dashboard was loaded is
#    checked by signing in through a port-forward and opening the "Homelab" folder.
kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-grafana:80/proxy/api/health"
```

Expected targets: apiserver, kubelet (three endpoints per node: kubelet, cAdvisor, probes),
CoreDNS, kube-state-metrics, node-exporter (one per node), the operator, Prometheus and Grafana.
There should be no scheduler, controller-manager, etcd or kube-proxy targets.

If Grafana is stuck in `CreateContainerConfigError`, the `grafana-admin` Secret is missing. If a
dashboard ConfigMap is not picked up, check its namespace is `monitoring` and it carries the label
`grafana_dashboard: "1"`.

## Cilium and Hubble metrics

Cilium's chart values (`kubernetes/bootstrap/cilium/values.yaml`) switch on the metrics endpoints
(agent, Hubble flows, operator) and the six Grafana dashboards, which land as ConfigMaps in
`monitoring` in the folder "Cilium". They do **not** switch on the chart's `ServiceMonitor`s: that
chart is installed by the platform stage before Argo CD and before this stack's CRDs exist, so a
`ServiceMonitor` there would fail on a cluster built from zero. The scrape configuration is
`monitors/cilium.yaml` instead: three `PodMonitor`s that select the pods directly (agent on port
`prometheus`, Hubble flows on `hubble-metrics`, operator on `prometheus`), applied by Argo CD after
the CRDs are there. Envoy is off, so it has no monitor. The Hubble metric list is short on
purpose (`dns`, `drop`, `tcp`, `flow`, `icmp`): flow metrics add many series, so watch the
Prometheus memory limit before adding more (`prometheus_tsdb_head_series` and the working set).

## Deferred

- **Logs (Loki).** Use the charts published by the `grafana-community` organisation (the Grafana
  subchart of this stack already comes from `oci://ghcr.io/grafana-community/helm-charts`), and
  check the exact chart location and version when the time comes. It needs a storage decision
  first (no StorageClass exists), and a Grafana data source ConfigMap
  in this namespace (label `grafana_datasource: "1"`), which the data source sidecar already
  watches.
- **Traces (Tempo).** After logs.
- **Istio metrics.** Istio ships ServiceMonitors/PodMonitors the same way; any dashboard ConfigMap
  it creates must land in `monitoring`.
- **kube-scheduler and etcd scraping.** Needs kubeadm changes first: set `bind-address` for the
  scheduler and controller-manager, and `listen-metrics-urls` for etcd, in the kubeadm
  configuration, then re-enable the `kubeScheduler`, `kubeEtcd` (and `kubeControllerManager`)
  switches and the matching `defaultRules.rules` groups in `values.yaml`.
- **Alertmanager and persistence.** When a StorageClass and a notification receiver exist.
