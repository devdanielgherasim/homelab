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
    about 16 GB of RAM in total, and a second node has its own: check the sum of the VM memory
    on the node before adding one.
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
      w.node == null || w.node == var.proxmox_node_name || contains(keys(var.proxmox_nodes), w.node)
    ])
    error_message = "A worker's node must be the primary node (proxmox_node_name) or one of the proxmox_nodes, and the node has to be added there first."
  }

  validation {
    condition     = alltrue([for name, w in var.workers : can(cidrhost(w.ip_address, 0))])
    error_message = "Worker ip_address must be an IPv4 address in CIDR form, for example 10.10.10.13/24."
  }
}

variable "proxmox_nodes" {
  description = <<-EOT
    More Proxmox nodes besides the primary one (proxmox_node_name), each standalone: a
    cluster of two would lose quorum whenever one machine is switched off. Keyed by the
    node's name, which is also its name in the Ansible inventory. A worker is placed on a node
    with `node = "<name>"`; without it, on the primary node. Empty for a single-host lab.

    endpoint  Address of the node's API, for example "https://10.10.10.20:8006/".
    slot      1 to 3. OpenTofu cannot create a provider per map entry, so there are three fixed
              provider slots, and the slot is the node's identity in the state. Never change it
              for a node that holds VMs (that would recreate them), and never reuse it.
    cpu_type  QEMU CPU type of the VMs on this node. The default is a fixed baseline: the
              machine may be older than the primary one (Ivy Bridge: AES-NI and SSE4.2, no AVX2),
              and what runs in a VM should not depend on which machine it landed on.

    API tokens are not part of this variable: they come from the environment
    (TF_VAR_proxmox_node_tokens), see scripts/bootstrap.sh.
  EOT
  type = map(object({
    endpoint = string
    slot     = number
    cpu_type = optional(string, "x86-64-v2-AES")
  }))
  default = {}

  validation {
    condition     = alltrue([for name, n in var.proxmox_nodes : contains([1, 2, 3], n.slot)])
    error_message = "The slot of a node is 1, 2 or 3 (there are three fixed provider slots)."
  }

  validation {
    condition     = length(distinct([for name, n in var.proxmox_nodes : n.slot])) == length(var.proxmox_nodes)
    error_message = "Every node needs its own slot."
  }

  validation {
    condition     = !contains(keys(var.proxmox_nodes), var.proxmox_node_name)
    error_message = "proxmox_nodes lists the nodes besides the primary one; the primary node is proxmox_node_name."
  }
}

variable "proxmox_node_tokens" {
  description = "API tokens of the nodes in proxmox_nodes, by node name, each as `user@realm!tokenid=secret`. From the environment (TF_VAR_proxmox_node_tokens, JSON), never a file in the repository."
  type        = map(string)
  default     = {}
  sensitive   = true
}
