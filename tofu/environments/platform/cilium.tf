# The CNI. It is installed here and not by Argo CD (ADR-0014): a network layer reconciled
# by a controller that runs on top of it can lock itself out. The values are the file in
# Git; only the API server address is private.
resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_chart_version

  values = [file("${local.repo_root}/kubernetes/bootstrap/cilium/values.yaml")]

  set_sensitive = [
    {
      name  = "k8sServiceHost"
      value = var.k8s_service_host
    },
  ]

  # A failed upgrade of the CNI is rolled back instead of being left half applied.
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  # The chart creates the Grafana dashboards as ConfigMaps in `monitoring`, which the
  # namespace resource creates (secrets.tf). It needs no CNI, so this ordering is safe on a
  # cluster that has none yet.
  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Addresses for LoadBalancer Services. They are real LAN addresses, so they come from
# variables, not from a file in Git. Nothing is announced until a Service carries the label
# and the CiliumL2AnnouncementPolicy in kubernetes/platform/networking/ selects it.
resource "kubectl_manifest" "lb_pool" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = var.lb_pool_name
    }
    spec = {
      blocks = [for b in var.lb_pool_blocks : { start = b.start, stop = b.stop }]
      serviceSelector = {
        matchLabels = var.lb_pool_label
      }
    }
  })

  server_side_apply = true
  force_conflicts   = true

  depends_on = [helm_release.cilium]
}
