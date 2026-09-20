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

variable "workers" {
  description = <<-EOT
    Kubernetes worker nodes, keyed by VM name. Adding an entry adds a worker;
    removing one removes it (drain it first, and clear its `protection` flag
    before the removal is applied). Workers hold no state and are rebuilt from
    Git, so this map is the whole definition of the worker pool.

    Sizing defaults match docs/architecture/infrastructure.md. The host has
    about 16 GB of RAM in total: check the sum of all VM memory before adding one.
  EOT
  type = map(object({
    vmid       = number
    ip_address = string # IPv4 in CIDR form
    cores      = optional(number, 2)
    memory     = optional(number, 3584) # MB
    disk_size  = optional(number, 64)   # GB
    node       = optional(string)       # Proxmox node; unset = the primary node (proxmox_node_name)
  }))

  validation {
    condition     = alltrue([for name, w in var.workers : can(regex("^[a-z][a-z0-9-]*[0-9]$", name))])
    error_message = "Worker names must be lowercase letters, digits and hyphens, and end in a digit (for example worker03)."
  }

  validation {
    condition     = alltrue([for name, w in var.workers : w.vmid >= 103 && w.vmid <= 199])
    error_message = "Worker VMIDs must be in 103-199 (101 and 102 belong to vpn01 and cp01, the 9000s to templates)."
  }

  validation {
    condition     = length(distinct([for name, w in var.workers : w.vmid])) == length(var.workers)
    error_message = "Every worker needs its own VMID."
  }

  validation {
    condition     = length(distinct([for name, w in var.workers : w.ip_address])) == length(var.workers)
    error_message = "Every worker needs its own IP address."
  }

  validation {
    condition = alltrue([
      for name, w in var.workers :
      w.node == null || w.node == var.proxmox_node_name || try(w.node == var.secondary_proxmox.node_name, false)
    ])
    error_message = "A worker's node must be the primary node (proxmox_node_name) or the secondary_proxmox node_name, and the secondary node has to be configured first."
  }

  validation {
    condition     = alltrue([for name, w in var.workers : can(cidrhost(w.ip_address, 0))])
    error_message = "Worker ip_address must be an IPv4 address in CIDR form, for example 10.10.10.13/24."
  }
}

variable "secondary_proxmox" {
  description = <<-EOT
    A second, standalone Proxmox node (not a cluster: two nodes would lose quorum whenever one
    is switched off). Leave null for a single-host lab. When set, a worker can be placed on it
    with `node = "<node_name>"`. The endpoint is the address of its API, for example
    "https://pve02.example.lan:8006/". Its API token is not a variable of this file: give it in the
    environment as TF_VAR_secondary_proxmox_api_token.
  EOT
  type = object({
    node_name = string
    endpoint  = string
  })
  default = null
}

variable "secondary_proxmox_api_token" {
  description = "API token of the second Proxmox node, as `user@realm!tokenid=secret`. From the environment (TF_VAR_secondary_proxmox_api_token), never a file in the repository."
  type        = string
  default     = null
  sensitive   = true
}

variable "secondary_cpu_type" {
  description = "QEMU CPU type for VMs on the second node. Its CPU is older than the first host's, so it gets a fixed baseline instead of `host` (Ivy Bridge: AES-NI and SSE4.2, no AVX2)."
  type        = string
  default     = "x86-64-v2-AES"
}
