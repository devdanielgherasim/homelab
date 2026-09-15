output "vpn01" {
  value = { vm_id = module.vpn01.vm_id, ip_address = module.vpn01.ip_address }
}

output "cp01" {
  value = { vm_id = module.cp01.vm_id, ip_address = module.cp01.ip_address }
}

output "worker01" {
  value = { vm_id = module.worker01.vm_id, ip_address = module.worker01.ip_address }
}

output "worker02" {
  value = { vm_id = module.worker02.vm_id, ip_address = module.worker02.ip_address }
}
