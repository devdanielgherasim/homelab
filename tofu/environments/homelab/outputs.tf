output "vpn01" {
  value = { vm_id = module.vpn01.vm_id, ip_address = module.vpn01.ip_address }
}

output "cp01" {
  value = { vm_id = module.cp01.vm_id, ip_address = module.cp01.ip_address }
}

output "workers" {
  description = "The worker pool, by name."
  value       = { for name, w in module.workers : name => { vm_id = w.vm_id, ip_address = w.ip_address } }
}

# Every VM with its role, in one map. ansible/inventories/production/tofu_inventory.py
# builds the Ansible inventory from this output, so nothing about the nodes is
# written down twice.
output "nodes" {
  description = "All lab VMs: name -> role, VMID and address (CIDR)."
  value = merge(
    {
      vpn01 = { role = "vpn", vm_id = module.vpn01.vm_id, ip_address = module.vpn01.ip_address }
      cp01  = { role = "control-plane", vm_id = module.cp01.vm_id, ip_address = module.cp01.ip_address }
    },
    { for name, w in module.workers : name => { role = "worker", vm_id = w.vm_id, ip_address = w.ip_address } },
  )
}
