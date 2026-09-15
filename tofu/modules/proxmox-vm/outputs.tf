output "vm_id" {
  description = "The Proxmox VMID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "The VM name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "ip_address" {
  description = "The static IP address assigned (as configured, not queried from the running VM)."
  value       = var.ip_address
}
