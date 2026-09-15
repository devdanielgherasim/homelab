terraform {
  required_version = ">= 1.8.0"

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
