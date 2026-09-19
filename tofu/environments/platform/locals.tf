locals {
  repo_root = "${path.module}/../../.."

  # One place for each version: the Argo CD chart version is whatever the self-managing
  # Application in Git says, so this stage and Argo CD can never install different charts.
  argocd_app           = yamldecode(file("${local.repo_root}/kubernetes/platform/apps/argocd.yaml"))
  argocd_chart_version = local.argocd_app.spec.sources[0].targetRevision
  argocd_chart_repo    = local.argocd_app.spec.sources[0].repoURL

  argocd_namespace_file = yamldecode(file("${local.repo_root}/kubernetes/bootstrap/argocd/namespace.yaml"))

  # projects.yaml holds one AppProject per YAML document. The documents are split here, not
  # with kubectl_file_documents, because that data source only knows its keys after apply and
  # for_each needs them at plan time. Keyed by the project name.
  argocd_projects = {
    for doc in split("\n---\n", file("${local.repo_root}/kubernetes/bootstrap/argocd/projects.yaml")) :
    yamldecode(doc).metadata.name => doc
    if try(yamldecode(doc).kind, "") == "AppProject"
  }

  monitoring_labels = {
    # node-exporter needs host access; everything else in the namespace is restricted-compliant.
    "pod-security.kubernetes.io/enforce" = "privileged"
    "pod-security.kubernetes.io/audit"   = "baseline"
    "pod-security.kubernetes.io/warn"    = "baseline"
  }
}
