terraform {
  required_version = ">= 1.9.0" # a variable validation may refer to another variable

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113"
    }
  }

  # No remote backend — local state, gitignored. Single operator,
  # zero-cost priority. See plans/2026-09-15-vm-provisioning.md.
}

provider "proxmox" {
  # Endpoint and API token come from PROXMOX_VE_ENDPOINT and
  # PROXMOX_VE_API_TOKEN environment variables — never from a file in
  # this repo. See docs/security/public-repository.md.
  insecure = var.proxmox_insecure # true by default: Proxmox's default cert is self-signed

  # No ssh {} block: not needed for the clone + cloud-init workflow this
  # environment uses (verified against the provider's clone guide — API
  # token auth alone is sufficient). Add one later only if a specific
  # feature needs it (e.g. direct file uploads).
}

# The extra, standalone Proxmox nodes (var.proxmox_nodes): three fixed provider slots, because a
# provider cannot be created per map entry. A slot nobody uses is never contacted. The endpoint
# comes from the node's entry and its token from TF_VAR_proxmox_node_tokens, since a provider
# cannot read a second set of environment variables. Each node has its own CA: SSL_CERT_FILE
# has to point at a bundle holding all of them (see docs/proxmox/installation.md).
locals {
  node_by_slot = { for name, n in var.proxmox_nodes : n.slot => name }
}

provider "proxmox" {
  alias     = "node1"
  endpoint  = try(var.proxmox_nodes[local.node_by_slot[1]].endpoint, null)
  api_token = try(var.proxmox_node_tokens[local.node_by_slot[1]], null)
  insecure  = var.proxmox_insecure
}

provider "proxmox" {
  alias     = "node2"
  endpoint  = try(var.proxmox_nodes[local.node_by_slot[2]].endpoint, null)
  api_token = try(var.proxmox_node_tokens[local.node_by_slot[2]], null)
  insecure  = var.proxmox_insecure
}

provider "proxmox" {
  alias     = "node3"
  endpoint  = try(var.proxmox_nodes[local.node_by_slot[3]].endpoint, null)
  api_token = try(var.proxmox_node_tokens[local.node_by_slot[3]], null)
  insecure  = var.proxmox_insecure
}
