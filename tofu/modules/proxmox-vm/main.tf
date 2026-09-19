# Clones a single VM from the Ubuntu 24.04 cloud-init template built by
# ansible/roles/proxmox_template/. See this directory's README for the
# known disk-resize-on-clone caveat before changing disk_size on an
# existing VM.

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vmid
  node_name = var.node_name
  tags      = var.tags

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  cpu {
    cores = var.cores
    type  = "host" # single physical host, no migration target — safe to expose host CPU features
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size
  }

  network_device {
    bridge = var.bridge
  }

  agent {
    enabled = true # guest side is installed by ansible/roles/qemu_guest_agent, not by the image
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_username
      keys     = var.ssh_public_keys
    }
  }
}
