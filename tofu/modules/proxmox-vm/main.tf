# Clones a single VM from the Ubuntu 24.04 cloud-init template built by
# ansible/roles/proxmox_template/. See this directory's README for the
# known disk-resize-on-clone caveat before changing disk_size on an
# existing VM.

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vmid
  node_name = var.node_name
  tags      = var.tags
  pool_id   = var.pool_id

  protection = var.protection
  on_boot    = var.on_boot

  # Never let an apply reboot a running node on its own. A change that needs a
  # reboot is applied to the VM configuration and takes effect at the next
  # reboot, which is then a deliberate, scheduled action.
  reboot_after_update = false

  # Boot order (the `startup` attribute) is deliberately not managed here: Proxmox
  # requires Sys.Modify on `/` to change it, which is far broader than this
  # token should have. It is a host setting and is applied by Ansible
  # (roles/proxmox_vm_startup); OpenTofu must not undo it.
  lifecycle {
    ignore_changes = [startup]
  }

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

    # The Ubuntu cloud image has no agent, so a new VM never reports its addresses until Ansible
    # has installed it, after this apply. The provider's default wait of 15 minutes per VM was
    # measured in the rebuild from zero (2026-09-20) and only ends in a warning, so wait one.
    timeout = "1m"
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
