output "argocd_admin_password" {
  description = "Initial admin password of Argo CD (user: admin). tofu output -raw argocd_admin_password"
  value       = random_password.argocd_admin.result
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Admin password of Grafana (user: admin). tofu output -raw grafana_admin_password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "argocd_chart_version" {
  description = "Argo CD chart version installed, read from kubernetes/platform/apps/argocd.yaml."
  value       = local.argocd_chart_version
}
