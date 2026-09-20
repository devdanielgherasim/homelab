# Argo CD, installed once from the same values file that its self-managing Application
# (kubernetes/platform/apps/argocd.yaml) uses, at the chart version that Application pins.
# After this, Argo CD manages itself and everything else from Git.

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name   = "argocd"
    labels = local.argocd_namespace_file.metadata.labels
  }

  depends_on = [helm_release.cilium]
}

# The admin password is generated, never chosen. Only its bcrypt hash reaches the cluster,
# so the initial admin Secret that Argo CD creates when no password is set never exists.
# Read the password with: tofu output -raw argocd_admin_password
resource "random_password" "argocd_admin" {
  length  = 32
  special = false
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = local.argocd_chart_repo
  chart      = "argo-cd"
  version    = local.argocd_chart_version

  values = [file("${local.repo_root}/kubernetes/bootstrap/argocd/values.yaml")]

  set_sensitive = [
    {
      name  = "configs.secret.argocdServerAdminPassword"
      value = random_password.argocd_admin.bcrypt_hash
    },
  ]

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600
}

# The AppProjects and the root Application, exactly as they are in Git. Once Argo CD runs,
# the `projects` and `platform` Applications keep them in sync; this stage only makes the
# first copy, which is why it never deletes them (apply_only).
resource "kubectl_manifest" "argocd_projects" {
  for_each  = local.argocd_projects
  yaml_body = each.value

  server_side_apply = true
  force_conflicts   = true
  apply_only        = true

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_root" {
  yaml_body = file("${local.repo_root}/kubernetes/bootstrap/argocd/root.yaml")

  server_side_apply = true
  force_conflicts   = true
  apply_only        = true

  # Once Argo CD runs it owns this object and writes its sync status into it, which changes
  # the hash of the live object (yaml_incluster) and would show as drift in every plan.
  # Verified: with this line, four plans in a row after Argo CD refreshes the object are
  # empty; without it the plan shows a change each time. OpenTofu warns that the element is
  # "redundant" because the attribute is computed, but it does suppress the diff.
  lifecycle {
    ignore_changes = [yaml_incluster]
  }

  depends_on = [kubectl_manifest.argocd_projects]
}
