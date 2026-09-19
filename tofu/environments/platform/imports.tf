# One-time adoption of the platform that was installed by hand before this stage existed
# (ADR-0016). On a fresh cluster none of these objects exists and the blocks do nothing.
# Once the adoption has been applied on the running cluster, this file can be deleted.

import {
  to = helm_release.cilium
  id = "kube-system/cilium"
}

import {
  to = kubernetes_namespace_v1.argocd
  id = "argocd"
}

import {
  to = helm_release.argocd
  id = "argocd/argocd"
}

import {
  for_each = local.argocd_projects
  to       = kubectl_manifest.argocd_projects[each.key]
  id       = "argoproj.io/v1alpha1//AppProject//${each.key}//argocd"
}

import {
  to = kubectl_manifest.argocd_root
  id = "argoproj.io/v1alpha1//Application//platform//argocd"
}

import {
  to = kubectl_manifest.lb_pool
  id = "cilium.io/v2//CiliumLoadBalancerIPPool//${var.lb_pool_name}"
}

import {
  to = kubernetes_namespace_v1.monitoring
  id = "monitoring"
}

import {
  to = kubernetes_secret_v1.grafana_admin
  id = "monitoring/grafana-admin"
}
