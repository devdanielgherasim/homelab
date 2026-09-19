# Sizing here mirrors docs/architecture/infrastructure.md's table exactly
# — keep both in sync if either changes. VMIDs 101-104 (100s = human
# workloads, distinct from the 9000 template range).

module "vpn01" {
  source = "../../modules/proxmox-vm"

  name      = "vpn01"
  vmid      = 101
  node_name = var.proxmox_node_name
  pool_id   = var.proxmox_pool


  cores     = 1
  memory    = 1024 # 512MB-1GB range per infrastructure.md; 1024 chosen as a clean value in range
  disk_size = 16

  ip_address = var.vpn01_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "vpn"]
}

module "cp01" {
  source = "../../modules/proxmox-vm"

  name      = "cp01"
  vmid      = 102
  node_name = var.proxmox_node_name
  pool_id   = var.proxmox_pool

  cores     = 2
  memory    = 3072 # 2.5-3GB range per infrastructure.md
  disk_size = 32

  ip_address = var.cp01_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "control-plane"]
}

# The worker pool. One module instance per entry of var.workers, so adding or
# removing a worker is a change to that map and nothing else.
module "workers" {
  source   = "../../modules/proxmox-vm"
  for_each = var.workers

  name      = each.key
  vmid      = each.value.vmid
  node_name = var.proxmox_node_name
  pool_id   = var.proxmox_pool

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  ip_address = each.value.ip_address
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}

# The two workers used to be separate module calls. These tell OpenTofu that the
# existing VMs are the same objects at their new addresses, so the refactor
# moves state and does not recreate anything. They can be deleted once the move
# has been applied everywhere.
moved {
  from = module.worker01
  to   = module.workers["worker01"]
}

moved {
  from = module.worker02
  to   = module.workers["worker02"]
}
