#!/usr/bin/env node
// SessionStart hook. Emits a short, cheap status brief — not project
// history, not a doc dump. Keeps this repo's "public by default" and
// "STATUS.md is the source of truth" facts visible without re-reading files.

import { spawnSync } from "node:child_process";

function git(args) {
  const r = spawnSync("git", args, { encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

const branch = git(["rev-parse", "--abbrev-ref", "HEAD"]) || "unknown";
const dirty = git(["status", "--porcelain"]);
const dirtyCount = dirty ? dirty.split("\n").filter(Boolean).length : 0;

const lines = [
  `homelab repo — branch: ${branch}, ${dirtyCount} uncommitted change(s).`,
  "Public-by-default: nothing sensitive gets committed — see AGENTS.md.",
  "STATUS.md is the source of truth for what is actually deployed — check it before claiming anything runs.",
];

console.log(lines.join("\n"));
process.exit(0);
