# Namespaces that need a Secret before Argo CD syncs the workload that reads it, and those
# Secrets. Nothing here is written by hand and nothing reaches Git: the values are generated
# at bootstrap and live in the cluster and in the (encrypted) state.

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = local.monitoring_labels
  }
}

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  # Keys the Grafana chart reads (grafana.admin.userKey / passwordKey in
  # kubernetes/platform/observability/values.yaml).
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  }
}
