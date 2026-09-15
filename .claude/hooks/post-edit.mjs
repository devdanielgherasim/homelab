#!/usr/bin/env node
// PostToolUse hook, matcher: Write|Edit.
// Runs on the SINGLE file just touched — never a repo-wide sweep (see
// AGENTS.md / hook cost principle). Best-effort: a missing tool warns,
// it never fails the hook. Never mutates infrastructure.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { extname } from "node:path";

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(""));
  });
}

function haveTool(name) {
  const probe = spawnSync(name, ["--version"], { stdio: "ignore" });
  return !probe.error;
}

function run(name, args, cwd) {
  const result = spawnSync(name, args, { cwd, encoding: "utf8" });
  if (result.error) {
    console.warn(`[post-edit] ${name} not runnable: ${result.error.message}`);
    return;
  }
  if (result.status !== 0) {
    console.warn(`[post-edit] ${name} ${args.join(" ")} exited ${result.status}:\n${result.stdout}\n${result.stderr}`);
  }
}

const raw = await readStdin();
let input;
try {
  input = JSON.parse(raw || "{}");
} catch {
  process.exit(0);
}

const filePath = input?.tool_input?.file_path;
if (typeof filePath !== "string" || !existsSync(filePath)) {
  process.exit(0);
}

// Secret scan — always, regardless of extension.
if (haveTool("gitleaks")) {
  run("gitleaks", ["detect", "--source", filePath, "--no-git", "-v"]);
} else {
  console.warn("[post-edit] gitleaks not on PATH — secret scan skipped for this file (see scripts/doctor.sh).");
}

const ext = extname(filePath).toLowerCase();
switch (ext) {
  case ".tf":
    if (haveTool("tofu")) run("tofu", ["fmt", filePath]);
    break;
  case ".yaml":
  case ".yml":
    if (haveTool("yamllint")) run("yamllint", ["-c", ".yamllint.yaml", filePath]);
    break;
  case ".sh":
    if (haveTool("shellcheck")) run("shellcheck", [filePath]);
    break;
  default:
    break; // .md and others: no formatter wired here by design
}

process.exit(0);
