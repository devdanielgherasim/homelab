# 0008. VPN-only management plane (Tailscale)

Status: Proposed
Date: 2026-09-15

## Context

The homelab's management plane (Proxmox UI, SSH, Kubernetes API, Argo CD,
Grafana) must never be exposed to the public Internet, per the project's
core security principle. Remote administration is still required, since
the lab isn't always accessed from the home network directly.

## Decision

Use Tailscale on a dedicated `vpn01` VM as the only remote-access path into
the management and node networks; no management port is ever forwarded
through the home router.

## Alternatives considered

- **Router port-forwarding + a traditional VPN (OpenVPN/WireGuard directly
  on the router)** — works, but couples remote access to router-level WAN
  exposure and manual key/port management; higher operational risk for a
  single maintainer.
- **No remote access (lab only reachable from the home LAN)** — simplest
  and most secure, but defeats the practical need to administer and
  demonstrate the lab remotely.
- **Cloudflare Tunnel or similar reverse-proxy tunnel** — good fit for
  exposing a specific public-facing app later, but not for administrative
  access to Proxmox/Kubernetes/SSH, which should stay on a private overlay
  network with device-level ACLs, not a public-reachable tunnel endpoint.

## Consequences

All administrative access depends on Tailscale's availability and the
`vpn01` VM being up — a deliberate trade-off, documented as the accepted
management-plane single point of entry in
[`../architecture/networking.md`](../architecture/networking.md#remote-access-and-vpn).
MFA and device ACLs on the Tailscale identity become load-bearing security
controls, not optional hardening.
