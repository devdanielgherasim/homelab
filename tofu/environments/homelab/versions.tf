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

# The second, standalone Proxmox node (var.secondary_proxmox). Unused, and never contacted,
# while no worker is placed on it. Its endpoint is a variable because a provider
# cannot read a second set of environment variables; its token comes from
# TF_VAR_secondary_proxmox_api_token. Each node has its own CA: SSL_CERT_FILE has to
# point at a bundle holding both (see docs/proxmox/installation.md).
provider "proxmox" {
  alias     = "secondary"
  endpoint  = try(var.secondary_proxmox.endpoint, null)
  api_token = var.secondary_proxmox_api_token
  insecure  = var.proxmox_insecure
}
