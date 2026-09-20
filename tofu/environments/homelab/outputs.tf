output "vpn01" {
  value = { vm_id = module.vpn01.vm_id, ip_address = module.vpn01.ip_address }
}

output "cp01" {
  value = { vm_id = module.cp01.vm_id, ip_address = module.cp01.ip_address }
}

output "workers" {
  description = "The worker pool, by name."
  value = merge(
    { for name, w in module.workers : name => { vm_id = w.vm_id, ip_address = w.ip_address } },
    { for name, w in module.workers_secondary : name => { vm_id = w.vm_id, ip_address = w.ip_address } },
  )
}

# Every VM with its role, the Proxmox host it is on and its address, in one map.
# ansible/inventories/production/tofu_inventory.py builds the Ansible inventory from
# this output, so nothing about the nodes is written down twice. `proxmox_host` is the
# Proxmox node name, which is also the name of that host in the Ansible inventory
# (pve01, pve02): the roles that act on a Proxmox host use it to pick that host's VMs.
output "nodes" {
  description = "All lab VMs: name -> role, Proxmox host, VMID and address (CIDR)."
  value = merge(
    {
      vpn01 = { role = "vpn", proxmox_host = var.proxmox_node_name, vm_id = module.vpn01.vm_id, ip_address = module.vpn01.ip_address }
      cp01  = { role = "control-plane", proxmox_host = var.proxmox_node_name, vm_id = module.cp01.vm_id, ip_address = module.cp01.ip_address }
    },
    { for name, w in module.workers : name => { role = "worker", proxmox_host = var.proxmox_node_name, vm_id = w.vm_id, ip_address = w.ip_address } },
    { for name, w in module.workers_secondary : name => { role = "worker", proxmox_host = local.secondary_workers[name].node, vm_id = w.vm_id, ip_address = w.ip_address } },
  )
}
