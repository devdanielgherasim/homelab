#!/usr/bin/env node
// PreToolUse hook, matcher: Bash.
// Blocks command patterns that would apply/destroy real infrastructure,
// per AGENTS.md's destructive-action policy. A block is not a refusal —
// it forces the human-approval conversation described there. This hook
// never itself executes, mutates, or approves anything.
//
// Contract: reads the tool-call JSON from stdin. Exit 0 = allow.
// Exit 2 + a reason on stderr = block, and the reason is shown to the
// agent/user so the conversation the policy requires can happen.

const DANGEROUS_PATTERNS = [
  { re: /\btofu\s+(apply|destroy)\b/i, reason: "OpenTofu apply/destroy" },
  { re: /\bterraform\s+(apply|destroy)\b/i, reason: "Terraform apply/destroy" },
  { re: /\bkubectl\s+.*\b(apply|delete|replace)\b/i, reason: "kubectl apply/delete/replace against a cluster" },
  { re: /\bkubeadm\s+reset\b/i, reason: "kubeadm reset" },
  { re: /\bhelm\s+(uninstall|delete)\b/i, reason: "helm uninstall/delete" },
  { re: /\bqm\s+(destroy|stop)\b/i, reason: "Proxmox qm destroy/stop" },
  { re: /\bpvesh\s+(delete|set)\b/i, reason: "Proxmox API mutation via pvesh" },
  { re: /\bpvesm\b.*\bremove\b/i, reason: "Proxmox storage removal" },
  { re: /\bmkfs(\.\w+)?\b/i, reason: "filesystem format" },
  { re: /\brm\s+-rf\s+\/(?!\S)/i, reason: "rm -rf / (root filesystem)" },
  { re: /\bgit\s+push\s+.*--force/i, reason: "git push --force" },
  { re: /\bgit\s+reset\s+--hard\b/i, reason: "git reset --hard" },
  { re: /\bgit\s+filter-(branch|repo)\b/i, reason: "Git history rewrite" },
  { re: /\bansible-vault\s+.*rekey\b/i, reason: "Ansible Vault rekey (credential rotation)" },
  { re: /\btailscale\s+.*\b(logout|down)\b.*--force/i, reason: "forced Tailscale disconnect" },
];

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(""));
  });
}

const raw = await readStdin();
let input;
try {
  input = JSON.parse(raw || "{}");
} catch {
  process.exit(0); // can't parse -> don't block on a guess
}

const command = input?.tool_input?.command;
if (typeof command !== "string" || command.length === 0) {
  process.exit(0);
}

for (const { re, reason } of DANGEROUS_PATTERNS) {
  if (re.test(command)) {
    process.stderr.write(
      `Blocked: command matches "${reason}" — a destructive-infrastructure pattern.\n` +
        `AGENTS.md requires explicit human approval (with impact, rollback, and expected downtime stated) before this runs.\n` +
        `Command: ${command}\n`
    );
    process.exit(2);
  }
}

process.exit(0);
