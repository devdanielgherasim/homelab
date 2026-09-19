# All three Kubernetes-facing providers read the same kubeconfig, fetched from the control
# plane by ansible/playbooks/k8s-kubeconfig.yml. It is a credential and stays out of Git.
provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

provider "kubectl" {
  config_path = pathexpand(var.kubeconfig_path)
}
