variable "proxmox_node_name" {
  description = "Proxmox node name."
  type        = string
  default     = "pve01"
}

variable "proxmox_insecure" {
  description = <<-EOT
    Skip TLS certificate verification. Leave false: Proxmox's certificate is
    signed by the cluster's own CA, so it verifies once that CA is trusted.
    Fetch it with `ansible-playbook ... proxmox-bootstrap.yml --tags tls_ca`
    and run OpenTofu with SSL_CERT_FILE pointing at it (Linux/WSL).
  EOT
  type        = bool
  default     = false
}

variable "proxmox_pool" {
  description = "Resource pool holding the lab VMs. OpenTofu's API token is scoped to it."
  type        = string
  default     = "homelab"
}

variable "ssh_public_keys" {
  description = "SSH public keys authorized on every VM's cloud-init user. Public keys only."
  type        = list(string)
}

variable "dns_servers" {
  description = "DNS servers for cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "network_gateway" {
  description = <<-EOT
    IPv4 gateway for all four VMs.

    SCOPE NOTE: docs/architecture/networking.md's target design has a
    separate management network and Kubernetes node network on separate
    bridges/VLANs. That segmentation isn't built yet — pve01 currently
    has a single bridge (vmbr0), so all VMs share one flat network here.
    Revisit this file when network segmentation is implemented.
  EOT
  type        = string
}

variable "vpn01_ip" {
  description = "vpn01's static IPv4 address in CIDR form (e.g. \"10.10.10.11/24\")."
  type        = string
}

variable "cp01_ip" {
  description = "cp01's static IPv4 address in CIDR form."
  type        = string
}

variable "worker01_ip" {
  description = "worker01's static IPv4 address in CIDR form."
  type        = string
}

variable "worker02_ip" {
  description = "worker02's static IPv4 address in CIDR form."
  type        = string
}
