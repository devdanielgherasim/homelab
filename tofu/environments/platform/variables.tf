variable "kubeconfig_path" {
  description = "Kubeconfig of the cluster, fetched by ansible/playbooks/k8s-kubeconfig.yml. Never committed."
  type        = string
  default     = "~/.kube/homelab.conf"
}

variable "k8s_service_host" {
  description = "Address of the Kubernetes API server, given to Cilium (kube-proxy replacement needs it before Services work). Network topology, so it is set in the gitignored terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "cilium_chart_version" {
  description = "Version of the cilium/cilium chart. Bump it together with the version note in kubernetes/bootstrap/cilium/README.md."
  type        = string
  default     = "1.20.2"
}

variable "lb_pool_blocks" {
  description = "Address ranges Cilium may give to LoadBalancer Services: free addresses on the nodes' subnet, outside the router's DHCP range. Real LAN addresses, so set in the gitignored terraform.tfvars."
  type = list(object({
    start = string
    stop  = string
  }))

  validation {
    condition     = length(var.lb_pool_blocks) > 0
    error_message = "Set at least one {start, stop} block."
  }

  validation {
    condition = alltrue([
      for b in var.lb_pool_blocks :
      can(cidrhost("${b.start}/32", 0)) && can(cidrhost("${b.stop}/32", 0))
    ])
    error_message = "start and stop must be IPv4 addresses."
  }
}

variable "lb_pool_name" {
  description = "Name of the CiliumLoadBalancerIPPool."
  type        = string
  default     = "private"
}

variable "lb_pool_label" {
  description = "Only Services carrying this label (key: value) receive an address from the pool. Must match kubernetes/platform/networking/l2-announcement-policy.yaml."
  type        = map(string)
  default     = { "homelab.io/lb-pool" = "private" }
}
