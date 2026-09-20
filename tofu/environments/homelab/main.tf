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

  cores = 2
  # 4GB, up from 3GB: with the platform running (Argo CD, Istio, Prometheus, Cilium) the node
  # used 2.3 of 2.9 GiB (kube-apiserver alone about 1.3 GiB). See infrastructure.md.
  memory    = 4096
  disk_size = 32

  ip_address = var.cp01_ip
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "control-plane"]
}

locals {
  # A worker is on the primary Proxmox node when it names no node or names that one; otherwise on
  # the node it names, which sits in one of the three provider slots (see var.proxmox_nodes).
  primary_workers = { for name, w in var.workers : name => w if w.node == null || w.node == var.proxmox_node_name }
  workers_on_slot = {
    for slot in [1, 2, 3] : slot => {
      for name, w in var.workers : name => w
      if w.node != null && try(var.proxmox_nodes[w.node].slot == slot, false)
    }
  }
}

# The worker pool. One module instance per entry of var.workers, so adding or
# removing a worker is a change to that map and nothing else. A provider cannot be
# chosen per for_each item, so the workers of each Proxmox node are their own module
# call: `workers` for the primary node and `workers_node1..3` for the nodes of
# var.proxmox_nodes, all the same module with another provider.
module "workers" {
  source   = "../../modules/proxmox-vm"
  for_each = local.primary_workers

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

# Workers on the extra Proxmox nodes. A node's slot decides which of these it uses.
module "workers_node1" {
  source    = "../../modules/proxmox-vm"
  for_each  = local.workers_on_slot[1]
  providers = { proxmox = proxmox.node1 }

  name      = each.key
  vmid      = each.value.vmid
  node_name = each.value.node
  pool_id   = var.proxmox_pool
  cpu_type  = var.proxmox_nodes[each.value.node].cpu_type

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  ip_address = each.value.ip_address
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}

module "workers_node2" {
  source    = "../../modules/proxmox-vm"
  for_each  = local.workers_on_slot[2]
  providers = { proxmox = proxmox.node2 }

  name      = each.key
  vmid      = each.value.vmid
  node_name = each.value.node
  pool_id   = var.proxmox_pool
  cpu_type  = var.proxmox_nodes[each.value.node].cpu_type

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  ip_address = each.value.ip_address
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}

module "workers_node3" {
  source    = "../../modules/proxmox-vm"
  for_each  = local.workers_on_slot[3]
  providers = { proxmox = proxmox.node3 }

  name      = each.key
  vmid      = each.value.vmid
  node_name = each.value.node
  pool_id   = var.proxmox_pool
  cpu_type  = var.proxmox_nodes[each.value.node].cpu_type

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  ip_address = each.value.ip_address
  gateway    = var.network_gateway

  ssh_public_keys = var.ssh_public_keys
  dns_servers     = var.dns_servers
  tags            = ["homelab", "worker"]
}

# The first extra node was called `workers_secondary` before there were slots.
moved {
  from = module.workers_secondary
  to   = module.workers_node1
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
