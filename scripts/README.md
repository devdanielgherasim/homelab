# scripts/

Small, self-contained helper scripts invoked by `Makefile` targets or CI.
Not a dumping ground — a script lands here only when it's reused from more
than one place (Makefile + CI + a hook, for example).

| Script | Used by | Purpose |
|---|---|---|
| `doctor.sh` | `make doctor` | Reports which required tools are present/missing/version-drifted. Installs nothing. |

Scripts here never touch real infrastructure (Proxmox, a real cluster)
without explicit human action — see
[`../AGENTS.md`](../AGENTS.md#destructive-action-policy).
