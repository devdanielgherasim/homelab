# Observability

Status: design reference — see [`STATUS.md`](../../STATUS.md).

16 GB RAM total means retention must be intentionally short. The
observability stack is itself a workload with resource requests/limits —
memory pressure is an intentional learning opportunity, but it must not
make the cluster permanently unstable.

| Signal | Tool | Initial retention / strategy |
|---|---|---|
| Metrics | Prometheus | 2–3 days; limited scrape frequency and resource requests |
| Dashboards | Grafana | Private/VPN access only (see [`../security/`](../security/)) |
| Logs | Loki | 2–3 days; avoid uncontrolled high-cardinality labels |
| Traces | Tempo | 1–2 days; sample aggressively |
| Network flows | Hubble | DNS, service connectivity, NetworkPolicy troubleshooting |

Alertmanager is added only where a specific alert justifies it — see
project principle of avoiding tools without a clear purpose
([`../../CLAUDE.md`](../../CLAUDE.md) / root instructions).

No dashboards or metrics endpoints are exposed outside the Tailscale
management plane — see [`../security/public-repository.md`](../security/public-repository.md).
