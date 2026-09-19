variable "name" {
  description = "VM name, as shown in the Proxmox UI (e.g. \"vpn01\")."
  type        = string
}

variable "vmid" {
  description = "Explicit Proxmox VMID. Chosen deliberately, not auto-assigned, so it stays predictable/documentable — see docs/architecture/infrastructure.md."
  type        = number
}

variable "node_name" {
  description = "Proxmox node name to place this VM on (e.g. \"pve01\")."
  type        = string
}

variable "template_vmid" {
  description = "VMID of the cloud-init template to clone (see ansible/roles/proxmox_template/, default template VMID 9000)."
  type        = number
  default     = 9000
}

variable "cores" {
  description = "vCPU count."
  type        = number
}

variable "memory" {
  description = "RAM in MB."
  type        = number
}

variable "disk_size" {
  description = "Disk size in GB. See the known clone-resize caveat in this module's README before changing this on an existing VM."
  type        = number
}

variable "datastore_id" {
  description = "Proxmox storage ID for the disk and Cloud-Init drive (check with `pvesm status` on the host)."
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Proxmox network bridge."
  type        = string
  default     = "vmbr0"
}

variable "ip_address" {
  description = "Static IPv4 address in CIDR form (e.g. \"10.10.20.11/24\"), per docs/architecture/networking.md's addressing plan."
  type        = string
}

variable "gateway" {
  description = "IPv4 gateway for this VM's network."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for cloud-init to configure."
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

variable "vm_username" {
  description = "Cloud-init user account created on first boot."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = "SSH public keys authorized for vm_username. Public keys only — never a private key or a secret."
  type        = list(string)
}

variable "tags" {
  description = "Proxmox tags for organization in the UI."
  type        = list(string)
  default     = []
}

variable "pool_id" {
  description = "Proxmox resource pool the VM belongs to. OpenTofu's token is scoped to this pool (see ansible/roles/proxmox_bootstrap/tasks/rbac.yml), so a VM outside it cannot be managed. Null = no pool."
  type        = string
  default     = null
}

variable "protection" {
  description = "Proxmox protection flag: while true, Proxmox refuses to delete the VM or its disks, which turns an accidental destroy into an error. Set it to false first when a VM really has to go."
  type        = bool
  default     = true
}

variable "on_boot" {
  description = "Start the VM automatically when the Proxmox host boots (the lab is powered on and off)."
  type        = bool
  default     = true
}
