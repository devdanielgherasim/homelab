# Sizing here mirrors docs/architecture/infrastructure.md's table exactly
# — keep both in sync if either changes. VMIDs 101-104 (100s = human
# workloads, distinct from the 9000 template range).

module "vpn01" {
  source = "../../modules/proxmox-vm"

  name      = "vpn01"
  vmid      = 101
  node_name = var.proxmox_node_name

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

  cores     = 2
  memory    = 3072 # 2.5-3GB range per infrastructure.md
  disk_size = 32

  ip_address = var.cp01_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "control-plane"]
}

module "worker01" {
  source = "../../modules/proxmox-vm"

  name      = "worker01"
  vmid      = 103
  node_name = var.proxmox_node_name

  cores     = 2
  memory    = 3584 # 3-3.5GB range per infrastructure.md
  disk_size = 64

  ip_address = var.worker01_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}

module "worker02" {
  source = "../../modules/proxmox-vm"

  name      = "worker02"
  vmid      = 104
  node_name = var.proxmox_node_name

  cores     = 2
  memory    = 3584
  disk_size = 64

  ip_address = var.worker02_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}
