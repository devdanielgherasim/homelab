# AI CLI Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a global (`~/.claude/`) MCP server + 5 skills that let Claude
Code delegate real work to Codex CLI, Gemini CLI, and GitHub Copilot CLI
(all already installed), plus a Perplexity hand-off draft tool that never
calls anything externally.

**Architecture:** One Node MCP server (`~/.claude/mcp-servers/ai-cli-orchestrator/`)
exposing 4 tools over stdio transport, registered at user scope via
`claude mcp add`. Each CLI-backed tool spawns its backend through a shared
`run-cli.mjs` helper (timeout + SIGTERM-then-SIGKILL + captured
stdout/stderr/exitCode, never swallowed). 5 skills under `~/.claude/skills/`
(one per backend + one top-level orchestrator) encode when to delegate,
citing `~/.ai/routing.md` rather than duplicating it.

**Tech Stack:** Node (ESM, `"type": "module"`), `@modelcontextprotocol/sdk@^1.30.0`,
`zod@^4.6.5` (peer dep of the SDK), Node's built-in `node:test` +
`node:assert/strict` for tests (no external test framework — avoids a
dependency neither this environment nor this user's other Node work needs).

**Spec:** `docs/superpowers/specs/2026-09-16-ai-cli-orchestrator-design.md`
— read it alongside this plan; this plan implements it task-by-task.

## Global Constraints

- Global scope only: everything lives under `~/.claude/` (`C:\Users\adria\.claude\`).
  Never touch this repo's own `.claude/` config.
- No tool may ever auto-post/auto-send externally. `draft_perplexity_handoff`
  makes zero network/process calls — pure string formatting.
- Every CLI-backed tool has a timeout (default 120s, overridable per call)
  and returns exit code + stderr on failure — never coerced into a success shape.
- No disk logging anywhere in the server. stdout/stderr/exitCode return
  directly in the tool response; nothing written to a log file.
- Ask before installing anything new outside this project's own
  `node_modules` (there is nothing else to ask about in this plan — only
  `@modelcontextprotocol/sdk` and `zod`, both already identified in the
  approved spec).
- `~/.claude` and `~/.ai` were added as working directories via `/add-dir`
  during brainstorming (2026-09-16) — Read/Write/Edit tools work there
  normally; this was verified, not assumed.
- Verified live during planning (2026-09-16), used as-is below, not
  re-derived: `@modelcontextprotocol/sdk` API shape (`McpServer`,
  `server.tool(name, description, zodShape, handler)`,
  `StdioServerTransport`, import paths `@modelcontextprotocol/sdk/server/mcp.js`
  and `@modelcontextprotocol/sdk/server/stdio.js`), and a real environment
  quirk: `node --test <directory>` fails to discover files on this
  Windows/Node v25.2.1 combination — bare `node --test` (no path argument)
  works and is used throughout.

---

### Task 1: Project scaffold + `run-cli.mjs` (the shared spawn/timeout helper)

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\package.json`
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\src\lib\run-cli.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\run-cli.test.mjs`

**Interfaces:**
- Produces: `runCli({ command, args = [], cwd, timeoutSec = 120 })` → `Promise<{ exitCode: number|null, signal: string|null, stdout: string, stderr: string, timedOut: boolean }>`. Every later task's tool wrapper imports and calls this.

- [ ] **Step 1: Create the project directory and `package.json`**

```bash
mkdir -p "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator/src/lib"
mkdir -p "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator/src/tools"
mkdir -p "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator/test"
```

Write `package.json`:

```json
{
  "name": "ai-cli-orchestrator",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "Local MCP server delegating to Codex CLI, Gemini CLI, and GitHub Copilot CLI, plus a Perplexity hand-off draft tool. Global, not tied to any one project.",
  "main": "index.mjs",
  "scripts": {
    "test": "node --test"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.30.0",
    "zod": "^4.6.5"
  }
}
```

- [ ] **Step 2: Install dependencies**

```bash
cd "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator"
npm install
```

Expected: `node_modules/@modelcontextprotocol/sdk` and `node_modules/zod` exist, `npm install` exits 0.

- [ ] **Step 3: Write the failing test for `run-cli.mjs`**

Create `test/run-cli.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { runCli } from "../src/lib/run-cli.mjs";

test("captures stdout and exit code 0 on success", async () => {
  const result = await runCli({
    command: process.execPath,
    args: ["-e", "console.log('hello')"],
  });
  assert.equal(result.exitCode, 0);
  assert.match(result.stdout, /hello/);
  assert.equal(result.timedOut, false);
});

test("captures non-zero exit code", async () => {
  const result = await runCli({
    command: process.execPath,
    args: ["-e", "process.exit(3)"],
  });
  assert.equal(result.exitCode, 3);
});

test("captures stderr", async () => {
  const result = await runCli({
    command: process.execPath,
    args: ["-e", "console.error('oops')"],
  });
  assert.match(result.stderr, /oops/);
});

test("respects cwd", async () => {
  const result = await runCli({
    command: process.execPath,
    args: ["-e", "console.log(process.cwd())"],
    cwd: "C:\\Users\\adria",
  });
  assert.match(result.stdout.trim().toLowerCase(), /c:\\users\\adria/i);
});

test(
  "times out and kills a long-running process",
  { timeout: 15000 },
  async () => {
    const result = await runCli({
      command: process.execPath,
      args: ["-e", "setTimeout(() => {}, 10000)"],
      timeoutSec: 0.3,
    });
    assert.equal(result.timedOut, true);
    assert.equal(result.exitCode, null);
  },
);
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
cd "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator"
npm test
```

Expected: FAIL — `Cannot find module '../src/lib/run-cli.mjs'` (file doesn't exist yet).

- [ ] **Step 5: Write `run-cli.mjs`**

```js
import { spawn } from "node:child_process";

const DEFAULT_TIMEOUT_SEC = 120;
const KILL_GRACE_MS = 5000;
const MAX_CAPTURE_CHARS = 10 * 1024 * 1024; // 10MB safety cap on internal capture

/**
 * Spawns `command` with `args`, captures stdout/stderr, and enforces a
 * timeout: SIGTERM first, then SIGKILL after a grace period if the
 * process hasn't exited. Never throws — failures (non-zero exit, spawn
 * error, timeout) all resolve with exitCode/stderr/timedOut set so the
 * caller can report them, never silently swallow them.
 */
export function runCli({ command, args = [], cwd, timeoutSec = DEFAULT_TIMEOUT_SEC }) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, shell: false });

    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let killTimer = null;
    let settled = false;

    const timeoutTimer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      killTimer = setTimeout(() => {
        child.kill("SIGKILL");
      }, KILL_GRACE_MS);
    }, timeoutSec * 1000);

    child.stdout.on("data", (chunk) => {
      if (stdout.length < MAX_CAPTURE_CHARS) stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      if (stderr.length < MAX_CAPTURE_CHARS) stderr += chunk.toString();
    });

    child.on("error", (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutTimer);
      if (killTimer) clearTimeout(killTimer);
      resolve({
        exitCode: null,
        signal: null,
        stdout,
        stderr: stderr + `\n[run-cli] spawn error: ${err.message}`,
        timedOut: false,
      });
    });

    child.on("close", (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutTimer);
      if (killTimer) clearTimeout(killTimer);
      resolve({ exitCode: code, signal, stdout, stderr, timedOut });
    });
  });
}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator"
npm test
```

Expected: all 5 tests pass (`pass 5`, `fail 0`).

- [ ] **Step 7: Commit**

There is no git repository at `~/.claude/` (verified during brainstorming),
so this step is: confirm the files are saved and move to Task 2. Nothing to
`git commit` here — record progress by checking this task's boxes.

---

### Task 2: `ask_codex` tool

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\src\tools\ask-codex.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\ask-codex.test.mjs`

**Interfaces:**
- Consumes: `runCli({ command, args, cwd, timeoutSec })` from Task 1.
- Produces: `createAskCodexTool(runCliFn = runCli)` → `{ name: "ask_codex", description: string, schema: object, handler: async (args) => CallToolResult }`. Task 6 imports `createAskCodexTool` and registers it on the server.

Codex is invoked as `codex exec "<prompt>" -o <tempfile>` — `-o` writes just
the final agent message to a file (verified via `codex exec --help`
2026-09-16), which is cleaner than parsing `--json` event streams for a v1.

- [ ] **Step 1: Write the failing test**

Create `test/ask-codex.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { createAskCodexTool } from "../src/tools/ask-codex.mjs";

test("ask_codex calls codex exec with -o and returns the file contents", async () => {
  let capturedCommand;
  let capturedArgs;
  const fakeRunCli = async ({ command, args }) => {
    capturedCommand = command;
    capturedArgs = args;
    // Simulate codex writing its final message to the -o file.
    const outputFileIndex = args.indexOf("-o") + 1;
    await writeFile(args[outputFileIndex], "42 is the answer.", "utf8");
    return { exitCode: 0, signal: null, stdout: "", stderr: "", timedOut: false };
  };

  const tool = createAskCodexTool(fakeRunCli);
  const result = await tool.handler({ prompt: "what is the answer?" });

  assert.equal(capturedCommand, "codex");
  assert.deepEqual(capturedArgs.slice(0, 2), ["exec", "what is the answer?"]);
  assert.equal(result.content[0].text, "42 is the answer.");
});

test("ask_codex surfaces non-zero exit code and stderr, never swallows it", async () => {
  const fakeRunCli = async () => ({
    exitCode: 1,
    signal: null,
    stdout: "",
    stderr: "authentication failed",
    timedOut: false,
  });

  const tool = createAskCodexTool(fakeRunCli);
  const result = await tool.handler({ prompt: "anything" });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /exit code 1/);
  assert.match(result.content[0].text, /authentication failed/);
});

test("ask_codex surfaces a timeout distinctly from a normal failure", async () => {
  const fakeRunCli = async () => ({
    exitCode: null,
    signal: "SIGKILL",
    stdout: "",
    stderr: "",
    timedOut: true,
  });

  const tool = createAskCodexTool(fakeRunCli);
  const result = await tool.handler({ prompt: "anything" });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /timed out/i);
});

test("ask_codex passes cwd and timeout_sec through to runCli", async () => {
  let capturedOpts;
  const fakeRunCli = async (opts) => {
    capturedOpts = opts;
    await writeFile(opts.args[opts.args.indexOf("-o") + 1], "ok", "utf8");
    return { exitCode: 0, signal: null, stdout: "", stderr: "", timedOut: false };
  };

  const tool = createAskCodexTool(fakeRunCli);
  await tool.handler({ prompt: "x", cwd: "C:\\some\\project", timeout_sec: 30 });

  assert.equal(capturedOpts.cwd, "C:\\some\\project");
  assert.equal(capturedOpts.timeoutSec, 30);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npm test
```

Expected: FAIL — `Cannot find module '../src/tools/ask-codex.mjs'`.

- [ ] **Step 3: Write `ask-codex.mjs`**

```js
import { z } from "zod";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readFile, rm } from "node:fs/promises";
import { runCli as defaultRunCli } from "../lib/run-cli.mjs";

const STDERR_TRUNCATE_CHARS = 4000;

export function createAskCodexTool(runCliFn = defaultRunCli) {
  return {
    name: "ask_codex",
    description:
      "Ask Codex CLI (gpt-5.5, non-interactive) a question or task. Use for " +
      "a second opinion, an independent parallel track, or a review — see " +
      "~/.ai/routing.md's Decision table. Codex is already paid for; use it " +
      "freely for that role.",
    schema: {
      prompt: z.string().describe("The instructions/question for Codex."),
      cwd: z.string().optional().describe("Working directory for Codex to operate in."),
      timeout_sec: z.number().optional().describe("Timeout in seconds (default 120)."),
    },
    handler: async (args) => {
      const outputFile = join(tmpdir(), `ask-codex-${randomUUID()}.txt`);
      const timeoutSec = args.timeout_sec ?? 120;

      const result = await runCliFn({
        command: "codex",
        args: ["exec", args.prompt, "-o", outputFile],
        cwd: args.cwd,
        timeoutSec,
      });

      if (result.timedOut) {
        await rm(outputFile, { force: true });
        return {
          isError: true,
          content: [{ type: "text", text: `codex exec timed out after ${timeoutSec}s.` }],
        };
      }

      if (result.exitCode !== 0) {
        await rm(outputFile, { force: true });
        const stderr = result.stderr.slice(0, STDERR_TRUNCATE_CHARS);
        return {
          isError: true,
          content: [
            {
              type: "text",
              text: `codex exec failed with exit code ${result.exitCode}.\nstderr:\n${stderr}`,
            },
          ],
        };
      }

      let finalMessage;
      try {
        finalMessage = await readFile(outputFile, "utf8");
      } catch (err) {
        return {
          isError: true,
          content: [
            {
              type: "text",
              text: `codex exec reported success but the output file was unreadable: ${err.message}`,
            },
          ],
        };
      } finally {
        await rm(outputFile, { force: true });
      }

      return { content: [{ type: "text", text: finalMessage }] };
    },
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npm test
```

Expected: all tests pass, including the 5 from Task 1 and the 4 new ones.

- [ ] **Step 5: Save progress**

No git repo at `~/.claude/` — check this task's boxes and move to Task 3.

---

### Task 3: `ask_gemini` tool

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\src\tools\ask-gemini.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\ask-gemini.test.mjs`

**Interfaces:**
- Consumes: `runCli` from Task 1 (same shape).
- Produces: `createAskGeminiTool(runCliFn = runCli)` → same tool shape as Task 2, name `ask_gemini`.

Gemini's shell shim errors under Git Bash specifically (verified
2026-09-16) — invoke via `node <path-to-bundle>/gemini.js -p "<prompt>"`
directly, bypassing the shim entirely. `context_files` are read and
prepended to the prompt as labeled blocks (Gemini CLI has no
"attach a file" flag; this is a real, working substitute, not an invented
CLI option).

- [ ] **Step 1: Write the failing test**

Create `test/ask-gemini.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createAskGeminiTool } from "../src/tools/ask-gemini.mjs";

test("ask_gemini calls the gemini bundle with -p and returns stdout", async () => {
  let capturedArgs;
  const fakeRunCli = async ({ args }) => {
    capturedArgs = args;
    return { exitCode: 0, signal: null, stdout: "Gemini's answer.", stderr: "", timedOut: false };
  };

  const tool = createAskGeminiTool(fakeRunCli);
  const result = await tool.handler({ prompt: "explain closures" });

  assert.equal(capturedArgs[capturedArgs.length - 2], "-p");
  assert.equal(capturedArgs[capturedArgs.length - 1], "explain closures");
  assert.equal(result.content[0].text, "Gemini's answer.");
});

test("ask_gemini prepends context_files content to the prompt", async () => {
  const dir = await mkdtemp(join(tmpdir(), "ask-gemini-test-"));
  const filePath = join(dir, "note.txt");
  await writeFile(filePath, "important context", "utf8");

  let capturedArgs;
  const fakeRunCli = async ({ args }) => {
    capturedArgs = args;
    return { exitCode: 0, signal: null, stdout: "ok", stderr: "", timedOut: false };
  };

  const tool = createAskGeminiTool(fakeRunCli);
  await tool.handler({ prompt: "summarize", context_files: [filePath] });

  const promptArg = capturedArgs[capturedArgs.length - 1];
  assert.match(promptArg, /important context/);
  assert.match(promptArg, /summarize/);

  await rm(dir, { recursive: true, force: true });
});

test("ask_gemini surfaces a missing context file as an error, not silently", async () => {
  const fakeRunCli = async () => {
    throw new Error("runCli should not be called if a context file is missing");
  };

  const tool = createAskGeminiTool(fakeRunCli);
  const result = await tool.handler({
    prompt: "summarize",
    context_files: ["C:\\does\\not\\exist.txt"],
  });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /does\\not\\exist\.txt/);
});

test("ask_gemini surfaces non-zero exit code and stderr", async () => {
  const fakeRunCli = async () => ({
    exitCode: 1,
    signal: null,
    stdout: "",
    stderr: "model unavailable",
    timedOut: false,
  });

  const tool = createAskGeminiTool(fakeRunCli);
  const result = await tool.handler({ prompt: "x" });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /model unavailable/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npm test
```

Expected: FAIL — `Cannot find module '../src/tools/ask-gemini.mjs'`.

- [ ] **Step 3: Write `ask-gemini.mjs`**

```js
import { z } from "zod";
import { readFile } from "node:fs/promises";
import { runCli as defaultRunCli } from "../lib/run-cli.mjs";

const STDERR_TRUNCATE_CHARS = 4000;

// Verified 2026-09-16: the `gemini` shell shim errors under Git Bash
// specifically; invoking node directly against the installed package's
// bundle sidesteps the shim entirely and works everywhere Node does.
const GEMINI_BUNDLE_PATH =
  "C:\\Users\\adria\\AppData\\Roaming\\npm\\node_modules\\@google\\gemini-cli\\bundle\\gemini.js";

async function buildPromptWithContext(prompt, contextFiles) {
  if (!contextFiles || contextFiles.length === 0) return prompt;

  const blocks = [];
  for (const filePath of contextFiles) {
    const contents = await readFile(filePath, "utf8"); // throws if missing — caller catches
    blocks.push(`=== context file: ${filePath} ===\n${contents}\n=== end context file ===`);
  }
  return `${blocks.join("\n\n")}\n\n${prompt}`;
}

export function createAskGeminiTool(runCliFn = defaultRunCli) {
  return {
    name: "ask_gemini",
    description:
      "Ask Gemini CLI a question or task, non-interactively. Use for " +
      "general reasoning and broad explanations that don't need this " +
      "session's own context. Gemini is free — use it liberally for that role.",
    schema: {
      prompt: z.string().describe("The question/task for Gemini."),
      context_files: z
        .array(z.string())
        .optional()
        .describe("Absolute paths to files whose contents get prepended as context."),
      cwd: z.string().optional().describe("Working directory for Gemini to operate in."),
      timeout_sec: z.number().optional().describe("Timeout in seconds (default 120)."),
    },
    handler: async (args) => {
      let fullPrompt;
      try {
        fullPrompt = await buildPromptWithContext(args.prompt, args.context_files);
      } catch (err) {
        return {
          isError: true,
          content: [{ type: "text", text: `Could not read a context file: ${err.message}` }],
        };
      }

      const timeoutSec = args.timeout_sec ?? 120;
      const result = await runCliFn({
        command: process.execPath,
        args: [GEMINI_BUNDLE_PATH, "-p", fullPrompt],
        cwd: args.cwd,
        timeoutSec,
      });

      if (result.timedOut) {
        return {
          isError: true,
          content: [{ type: "text", text: `gemini -p timed out after ${timeoutSec}s.` }],
        };
      }
      if (result.exitCode !== 0) {
        const stderr = result.stderr.slice(0, STDERR_TRUNCATE_CHARS);
        return {
          isError: true,
          content: [
            { type: "text", text: `gemini -p failed with exit code ${result.exitCode}.\nstderr:\n${stderr}` },
          ],
        };
      }

      return { content: [{ type: "text", text: result.stdout }] };
    },
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 4.

---

### Task 4: `ask_copilot` tool

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\src\tools\ask-copilot.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\ask-copilot.test.mjs`

**Interfaces:**
- Consumes: `runCli` from Task 1.
- Produces: `createAskCopilotTool(runCliFn = runCli)` → same tool shape, name `ask_copilot`.

Copilot CLI (already installed via WinGet — no download needed, corrected
during brainstorming) is invoked as `copilot -p "<prompt>" -s`; `-s/--silent`
gives just the agent's response text on stdout.

- [ ] **Step 1: Write the failing test**

Create `test/ask-copilot.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createAskCopilotTool } from "../src/tools/ask-copilot.mjs";

test("ask_copilot calls copilot -p -s and returns stdout", async () => {
  let capturedCommand;
  let capturedArgs;
  const fakeRunCli = async ({ command, args }) => {
    capturedCommand = command;
    capturedArgs = args;
    return { exitCode: 0, signal: null, stdout: "Fixed the off-by-one.", stderr: "", timedOut: false };
  };

  const tool = createAskCopilotTool(fakeRunCli);
  const result = await tool.handler({ prompt: "fix the loop bound in foo.js" });

  assert.equal(capturedCommand, "copilot");
  assert.ok(capturedArgs.includes("-p"));
  assert.ok(capturedArgs.includes("fix the loop bound in foo.js"));
  assert.ok(capturedArgs.includes("-s"));
  assert.equal(result.content[0].text, "Fixed the off-by-one.");
});

test("ask_copilot passes cwd through so edits land in the right repo", async () => {
  let capturedCwd;
  const fakeRunCli = async ({ cwd }) => {
    capturedCwd = cwd;
    return { exitCode: 0, signal: null, stdout: "ok", stderr: "", timedOut: false };
  };

  const tool = createAskCopilotTool(fakeRunCli);
  await tool.handler({ prompt: "x", cwd: "E:\\some\\repo" });

  assert.equal(capturedCwd, "E:\\some\\repo");
});

test("ask_copilot surfaces non-zero exit code and stderr", async () => {
  const fakeRunCli = async () => ({
    exitCode: 2,
    signal: null,
    stdout: "",
    stderr: "not logged in",
    timedOut: false,
  });

  const tool = createAskCopilotTool(fakeRunCli);
  const result = await tool.handler({ prompt: "x" });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /not logged in/);
});

test("ask_copilot surfaces a timeout distinctly", async () => {
  const fakeRunCli = async () => ({
    exitCode: null,
    signal: "SIGKILL",
    stdout: "",
    stderr: "",
    timedOut: true,
  });

  const tool = createAskCopilotTool(fakeRunCli);
  const result = await tool.handler({ prompt: "x" });

  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /timed out/i);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npm test
```

Expected: FAIL — `Cannot find module '../src/tools/ask-copilot.mjs'`.

- [ ] **Step 3: Write `ask-copilot.mjs`**

```js
import { z } from "zod";
import { runCli as defaultRunCli } from "../lib/run-cli.mjs";

const STDERR_TRUNCATE_CHARS = 4000;

export function createAskCopilotTool(runCliFn = defaultRunCli) {
  return {
    name: "ask_copilot",
    description:
      "Ask GitHub Copilot CLI to do a concrete, git/repo-aware coding task " +
      "(edit a file, fix a bug, suggest a shell command), non-interactively. " +
      "Copilot is free — use it liberally for concrete code edits.",
    schema: {
      prompt: z.string().describe("The coding task/question for Copilot."),
      cwd: z.string().optional().describe("Working directory (repo) for Copilot to operate in."),
      timeout_sec: z.number().optional().describe("Timeout in seconds (default 120)."),
    },
    handler: async (args) => {
      const timeoutSec = args.timeout_sec ?? 120;
      const result = await runCliFn({
        command: "copilot",
        args: ["-p", args.prompt, "-s"],
        cwd: args.cwd,
        timeoutSec,
      });

      if (result.timedOut) {
        return {
          isError: true,
          content: [{ type: "text", text: `copilot -p timed out after ${timeoutSec}s.` }],
        };
      }
      if (result.exitCode !== 0) {
        const stderr = result.stderr.slice(0, STDERR_TRUNCATE_CHARS);
        return {
          isError: true,
          content: [
            { type: "text", text: `copilot -p failed with exit code ${result.exitCode}.\nstderr:\n${stderr}` },
          ],
        };
      }

      return { content: [{ type: "text", text: result.stdout }] };
    },
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 5.

---

### Task 5: `draft_perplexity_handoff` tool

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\src\tools\draft-perplexity-handoff.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\draft-perplexity-handoff.test.mjs`

**Interfaces:**
- Consumes: nothing (pure function, no `runCli`).
- Produces: `createDraftPerplexityHandoffTool()` → same tool shape, name `draft_perplexity_handoff`.

This tool makes **zero** network/process calls — structurally incapable of
auto-sending anything, per the spec's hard constraint.

- [ ] **Step 1: Write the failing test**

Create `test/draft-perplexity-handoff.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createDraftPerplexityHandoffTool } from "../src/tools/draft-perplexity-handoff.mjs";

test("draft_perplexity_handoff formats a self-contained prompt with context", () => {
  const tool = createDraftPerplexityHandoffTool();
  const result = tool.handler({
    question: "What is the current stable OpenTofu version?",
    context: "Homelab repo pins OpenTofu in mise.toml.",
  });

  assert.match(result.content[0].text, /What is the current stable OpenTofu version\?/);
  assert.match(result.content[0].text, /Homelab repo pins OpenTofu in mise\.toml\./);
  assert.match(result.content[0].text, /paste this into Perplexity/i);
});

test("draft_perplexity_handoff works with no context given", () => {
  const tool = createDraftPerplexityHandoffTool();
  const result = tool.handler({ question: "Is Node 25 the current LTS?" });

  assert.match(result.content[0].text, /Is Node 25 the current LTS\?/);
  assert.equal(result.isError, undefined);
});

test("draft_perplexity_handoff never returns isError — it cannot fail, it only formats text", () => {
  const tool = createDraftPerplexityHandoffTool();
  const result = tool.handler({ question: "x" });
  assert.equal(result.isError, undefined);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npm test
```

Expected: FAIL — `Cannot find module '../src/tools/draft-perplexity-handoff.mjs'`.

- [ ] **Step 3: Write `draft-perplexity-handoff.mjs`**

```js
import { z } from "zod";

export function createDraftPerplexityHandoffTool() {
  return {
    name: "draft_perplexity_handoff",
    description:
      "Draft a self-contained prompt for Perplexity (live web) and a note " +
      "to paste it manually. Makes NO network or process call — Perplexity " +
      "has no API by design (~/.ai/routing.md AD-4). Never auto-sent.",
    schema: {
      question: z.string().describe("The tight, self-contained question for Perplexity."),
      context: z.string().optional().describe("Exact versions/constraints Perplexity needs, since it has none of this session's context."),
    },
    handler: (args) => {
      const parts = [args.question];
      if (args.context) parts.push(`\nContext: ${args.context}`);
      const draft = parts.join("\n");

      return {
        content: [
          {
            type: "text",
            text:
              `--- Paste this into Perplexity manually ---\n${draft}\n` +
              `--- end ---\n\n` +
              `After you get an answer, paste the distilled result (not the whole ` +
              `transcript) back into the active plans/*.md file or the relevant ` +
              `~/.ai/memory/*.md file, with the source URL — per ~/.ai/routing.md's ` +
              `"Perplexity anti-black-hole rule."`,
          },
        ],
      };
    },
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npm test
```

Expected: all tests pass.

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 6.

---

### Task 6: MCP server entry point (`index.mjs`) wiring all 4 tools

**Files:**
- Create: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\index.mjs`
- Test: `C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\test\index.test.mjs`

**Interfaces:**
- Consumes: `createAskCodexTool`, `createAskGeminiTool`, `createAskCopilotTool`, `createDraftPerplexityHandoffTool` from Tasks 2-5 (each already default-wired to the real `runCli`).
- Produces: a runnable stdio MCP server; no further task depends on this module's exports (it's the executable entry point), only on it running correctly.

This task's test imports the 4 tool factories directly and checks their
shape (name/description/schema/handler present and correctly typed)
rather than spinning up a full stdio client — a real, fast check that the
tools are wired with the right names, without the complexity of a live
subprocess-based MCP client in a unit test.

- [ ] **Step 1: Write the failing test**

Create `test/index.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createAskCodexTool } from "../src/tools/ask-codex.mjs";
import { createAskGeminiTool } from "../src/tools/ask-gemini.mjs";
import { createAskCopilotTool } from "../src/tools/ask-copilot.mjs";
import { createDraftPerplexityHandoffTool } from "../src/tools/draft-perplexity-handoff.mjs";
import { ALL_TOOLS } from "../index.mjs";

test("index.mjs exports exactly the 4 expected tools by name", () => {
  const names = ALL_TOOLS.map((t) => t.name).sort();
  assert.deepEqual(names, [
    "ask_codex",
    "ask_copilot",
    "ask_gemini",
    "draft_perplexity_handoff",
  ]);
});

test("every exported tool has a name, description, schema, and handler", () => {
  for (const tool of ALL_TOOLS) {
    assert.equal(typeof tool.name, "string");
    assert.equal(typeof tool.description, "string");
    assert.equal(typeof tool.schema, "object");
    assert.equal(typeof tool.handler, "function");
  }
});

test("each factory used in index.mjs produces a tool with the matching name", () => {
  assert.equal(createAskCodexTool().name, "ask_codex");
  assert.equal(createAskGeminiTool().name, "ask_gemini");
  assert.equal(createAskCopilotTool().name, "ask_copilot");
  assert.equal(createDraftPerplexityHandoffTool().name, "draft_perplexity_handoff");
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
npm test
```

Expected: FAIL — `Cannot find module '../index.mjs'` (or `ALL_TOOLS` is
undefined once the file exists but before it's finished — write it
fully in the next step either way).

- [ ] **Step 3: Write `index.mjs`**

```js
#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createAskCodexTool } from "./src/tools/ask-codex.mjs";
import { createAskGeminiTool } from "./src/tools/ask-gemini.mjs";
import { createAskCopilotTool } from "./src/tools/ask-copilot.mjs";
import { createDraftPerplexityHandoffTool } from "./src/tools/draft-perplexity-handoff.mjs";

export const ALL_TOOLS = [
  createAskCodexTool(),
  createAskGeminiTool(),
  createAskCopilotTool(),
  createDraftPerplexityHandoffTool(),
];

async function main() {
  const server = new McpServer({ name: "ai-cli-orchestrator", version: "0.1.0" });

  for (const tool of ALL_TOOLS) {
    server.tool(tool.name, tool.description, tool.schema, tool.handler);
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

// Only auto-start when run directly (`node index.mjs`), not when imported
// by test/index.test.mjs above.
if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, "/")}`) {
  main().catch((err) => {
    console.error("ai-cli-orchestrator failed to start:", err);
    process.exit(1);
  });
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
npm test
```

Expected: all tests across every file pass — this is the full test suite now.

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 7.

---

### Task 7: Register the server with Claude Code and verify against the real backends

**Files:** none created — this task registers and exercises what Tasks 1-6 built.

**Interfaces:** none new.

This is the task where real Codex/Gemini/Copilot get invoked (not fakes) —
the actual end-to-end validation gate. **Ask the user before running this
task** if it hasn't already been explicitly approved in the current
session, since it makes real calls to Codex (paid) and starts a
long-running local process (the MCP server).

- [ ] **Step 1: Register the server at user scope**

```bash
claude mcp add ai-cli-orchestrator -s user -- node "C:\Users\adria\.claude\mcp-servers\ai-cli-orchestrator\index.mjs"
```

Expected: command exits 0.

- [ ] **Step 2: Confirm it's registered and connects**

```bash
claude mcp list
claude mcp get ai-cli-orchestrator
```

Expected: `ai-cli-orchestrator` appears, health-checked/connected, not
"⏸ Pending approval".

- [ ] **Step 3: Real end-to-end call — `ask_gemini`**

Start a **new** Claude Code session (so the newly-registered server is
picked up) and ask it to call `ask_gemini` with a trivial prompt, e.g.
"use ask_gemini to ask: what is 2+2, answer in one word". Expected: a real
Gemini response comes back through the tool, not an error.

- [ ] **Step 4: Real end-to-end call — `ask_copilot`**

Same session, ask it to call `ask_copilot` with a trivial prompt, e.g. "use
ask_copilot to ask: what does the git command 'git rebase -i' do, answer in
one sentence". Expected: a real Copilot response comes back.

- [ ] **Step 5: Real end-to-end call — `ask_codex`**

Same session, ask it to call `ask_codex` with a trivial prompt. **This
consumes real Codex usage** — confirm with the user before this specific
step if any doubt remains. Expected: a real Codex response comes back, and
the temp `-o` file it wrote is gone afterward (`ls` the temp dir before/after
to confirm cleanup, e.g. `ls /c/Users/adria/AppData/Local/Temp | grep ask-codex-` returns nothing).

- [ ] **Step 6: Real end-to-end call — `draft_perplexity_handoff`**

Ask it to call `draft_perplexity_handoff` with a sample question. Expected:
a formatted draft comes back; confirm nothing was sent anywhere (no
network call happened — this is inherent to the tool's implementation, not
something to separately verify via a network monitor).

- [ ] **Step 7: Real failure-path check**

Ask it to call `ask_codex` (or any backend) with `timeout_sec: 1` and a
prompt substantial enough that the backend can't finish in 1 second.
Expected: the tool returns `isError: true` with a "timed out after 1s"
message — confirms the timeout path works against a real process, not
just the Task 1-4 fakes.

---

### Task 8: Backend-specific skills (`ask-codex`, `ask-gemini`, `ask-copilot`, `perplexity-handoff`)

**Files:**
- Create: `C:\Users\adria\.claude\skills\ask-codex\SKILL.md`
- Create: `C:\Users\adria\.claude\skills\ask-gemini\SKILL.md`
- Create: `C:\Users\adria\.claude\skills\ask-copilot\SKILL.md`
- Create: `C:\Users\adria\.claude\skills\perplexity-handoff\SKILL.md`

**Interfaces:** none (documentation only — no later task imports these).

Each skill: short, cites `~/.ai/routing.md` rather than duplicating its
content, states the one MCP tool to call.

- [ ] **Step 1: Write `ask-codex/SKILL.md`**

```markdown
---
name: ask-codex
description: >
  Delegate a task to Codex CLI via the ask_codex MCP tool — for a second
  opinion, an independent parallel track, or a review. Use when the task
  doesn't depend on this session's own already-loaded context.
---

# ask-codex

Call the `ask_codex` MCP tool (from the `ai-cli-orchestrator` server) —
don't shell out to `codex exec` directly; the tool already handles
timeout and error surfacing.

## When

See `~/.ai/routing.md`'s Decision table — Codex is the primary choice for:
"second opinion / parallel independent track / cross-check a review" and
security/IaC review where Codex holds the matching skill. Codex is already
paid for; use it for that role without hesitation.

## How

`ask_codex(prompt, cwd?, timeout_sec?)` — `cwd` should point at the
relevant repo if the task is repo-specific. Default timeout 120s; raise
`timeout_sec` for a heavier reasoning pass.

## Don't

Don't forward a prompt describing a destructive action (infra changes,
deletions) — scope the prompt to something safe for Codex to reason about,
never a blind pass-through of a dangerous request.
```

- [ ] **Step 2: Write `ask-gemini/SKILL.md`**

```markdown
---
name: ask-gemini
description: >
  Delegate general reasoning or a broad explanation to Gemini CLI via the
  ask_gemini MCP tool. Gemini is free — prefer it over doing the reasoning
  in Claude directly when the task doesn't need this session's own context.
---

# ask-gemini

Call the `ask_gemini` MCP tool (from the `ai-cli-orchestrator` server).

## When

Free, general-purpose reasoning/explanation that doesn't depend on files
already read or decisions already made in this session. Not yet in
`~/.ai/routing.md`'s table (added 2026-09-16) — this is the primary
free-tier delegate for broad reasoning, distinct from Copilot's
code-edit-focused role.

## How

`ask_gemini(prompt, context_files?, cwd?, timeout_sec?)` — pass
`context_files` (absolute paths) instead of pasting file contents into the
prompt yourself; the tool reads and prepends them. Default timeout 120s.

## Known gotcha

The `gemini` shell command itself is flaky under some shells on this
machine (verified 2026-09-16) — irrelevant when using this MCP tool, which
invokes the underlying package directly and doesn't hit that path.
```

- [ ] **Step 3: Write `ask-copilot/SKILL.md`**

```markdown
---
name: ask-copilot
description: >
  Delegate a concrete, repo-aware code edit or shell-command question to
  GitHub Copilot CLI via the ask_copilot MCP tool. Copilot is free —
  prefer it for hands-on code edits over doing them in Claude directly.
---

# ask-copilot

Call the `ask_copilot` MCP tool (from the `ai-cli-orchestrator` server).

## When

Free, concrete coding tasks: fix a specific bug, make a targeted edit,
explain/suggest a shell command, git-aware changes. Not yet in
`~/.ai/routing.md`'s table (added 2026-09-16) — this is the primary
free-tier delegate for hands-on code edits, distinct from Gemini's
broader-reasoning role.

## How

`ask_copilot(prompt, cwd?, timeout_sec?)` — always pass `cwd` pointing at
the target repo so edits land in the right place. Default timeout 120s.

## Don't

Don't forward a prompt describing a destructive action — same rule as
`ask-codex`.
```

- [ ] **Step 4: Write `perplexity-handoff/SKILL.md`**

```markdown
---
name: perplexity-handoff
description: >
  Draft a self-contained Perplexity prompt via the draft_perplexity_handoff
  MCP tool for live-web questions — Perplexity has no API, so this never
  calls anything; it hands you text to paste manually.
---

# perplexity-handoff

Call the `draft_perplexity_handoff` MCP tool (from the `ai-cli-orchestrator`
server) — never attempt to reach Perplexity any other way; it has no API,
by design (see `~/.ai/routing.md`, AD-4).

## When

Any time-sensitive or external-web question — see `~/.ai/routing.md`'s
Decision table: "Perplexity — only tool with live web."

## How

`draft_perplexity_handoff(question, context)` returns a formatted draft
and a reminder to paste the distilled answer back into the active
`plans/*.md` or `~/.ai/memory/*.md` file with its source URL — the
"Perplexity anti-black-hole rule" already in `routing.md`. This tool makes
no network call; you paste the draft into Perplexity yourself, then
paste the answer back yourself.
```

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 9.

---

### Task 9: Top-level `ai-orchestrator` skill

**Files:**
- Create: `C:\Users\adria\.claude\skills\ai-orchestrator\SKILL.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write `ai-orchestrator/SKILL.md`**

```markdown
---
name: ai-orchestrator
description: >
  Decide whether to delegate a task to Codex/Gemini/Copilot (via the
  ai-cli-orchestrator MCP server) or do it directly in Claude. Use at the
  start of any implementation/research/explanation/edit task to check
  whether delegating saves tokens without costing more than it saves.
---

# ai-orchestrator

Strong default bias toward delegating — not a hard-forced rule (see
`~/.ai/memory/decisions.md` for why this doesn't override AD-5's
"nothing here is automated" — Claude still decides per-turn).

## Algorithm

1. **New delegable task arrives** (implementation, research, explanation,
   a concrete code edit). Ask: does this depend heavily on this session's
   own already-loaded context (files already read here, decisions already
   made in this conversation) such that re-explaining it to a cold
   delegate would cost more than delegating saves?
   - **No** → delegate:
     - Concrete code edit / git-aware task → `ask-copilot` skill.
     - General reasoning / broad explanation → `ask-gemini` skill.
     - Second opinion / independent parallel track / review → `ask-codex` skill.
     - Live web / current info → `perplexity-handoff` skill.
   - **Yes** → do it directly in Claude.
2. **Never delegated:**
   - Final synthesis across multiple backend outputs — that judgment call
     is Claude's, always.
   - Anything touching a destructive-action policy (infra changes,
     deletions, credential rotation) — a delegate's prompt must be scoped
     safely, never a blind forward of a dangerous request.
   - Anything requiring a project-local skill/hook a delegate CLI can't
     read (e.g. this repository's own `.claude/skills/`).
3. **Multiple backends on the same question** → synthesize
   (agreement/disagreement + Claude's own judgment), never concatenate
   raw outputs unfiltered.

## See also

- `~/.ai/routing.md` — the underlying manual routing convention this
  skill's algorithm is built on top of; read it for the full picture
  across Claude Code, Codex CLI, and Perplexity, not just this skill's
  summary.
- `ask-codex`, `ask-gemini`, `ask-copilot`, `perplexity-handoff` — the
  four backend-specific skills this one routes to.
```

- [ ] **Step 2: Save progress** — check this task's boxes, move to Task 10.

---

### Task 10: Update `~/.ai/routing.md`

**Files:**
- Modify: `C:\Users\adria\.ai\routing.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Read the current file**

```bash
cat "/c/Users/adria/.ai/routing.md"
```

Confirm the exact current text of the "Decision table" section before
editing (already read once during brainstorming 2026-09-16 — re-read here
in case it changed since).

- [ ] **Step 2: Add two rows to the Decision table**

Insert these two rows into the existing Decision table (keep the existing
rows and formatting exactly as-is, add these among them in a sensible
place — e.g. right after the "Large mechanical batch edits" row):

```markdown
| Free general reasoning / broad explanation | **Gemini CLI** (`ask-gemini` skill, `ai-cli-orchestrator` MCP server) | Free, no cap pressure | Claude directly if the task needs this session's own context |
| Free concrete code edit / git-aware task | **Copilot CLI** (`ask-copilot` skill, `ai-cli-orchestrator` MCP server) | Free, no cap pressure | Claude directly if the task needs this session's own context |
```

- [ ] **Step 3: Add a new section documenting the MCP tools**

Append this section after the existing "Capability map" section (before
"Perplexity anti-black-hole rule"):

```markdown
## AI CLI orchestrator (added 2026-09-16)

A local MCP server (`~/.claude/mcp-servers/ai-cli-orchestrator/`,
registered at user scope) exposes `ask_codex`, `ask_gemini`, `ask_copilot`,
and `draft_perplexity_handoff` as callable tools — see the
`ai-orchestrator` skill (`~/.claude/skills/ai-orchestrator/SKILL.md`) for
the delegation algorithm, and the per-backend skills (`ask-codex`,
`ask-gemini`, `ask-copilot`, `perplexity-handoff`) for when/how to call
each. Codex CLI reads this file but cannot call these MCP tools the same
way Claude Code does — for Codex, these rows describe Claude's delegation
behavior, not something Codex itself should attempt to replicate via its
own tool-calling.

Design spec: `E:\personal-projects\homelab\docs\superpowers\specs\2026-09-16-ai-cli-orchestrator-design.md`
(lives in that repo only because neither `~/.claude/` nor `~/.ai/` is a
git repository — the feature itself is not specific to that project).
```

- [ ] **Step 4: Verify the file is still valid markdown**

```bash
py -3 -c "
import re
content = open('/c/Users/adria/.ai/routing.md', encoding='utf-8').read()
assert '## AI CLI orchestrator' in content
assert 'Gemini CLI' in content
assert 'Copilot CLI' in content
print('OK: sections present')
"
```

Expected: `OK: sections present`.

- [ ] **Step 5: Save progress** — check this task's boxes, move to Task 11.

---

### Task 11: Add a decision entry to `~/.ai/memory/decisions.md`

**Files:**
- Modify: `C:\Users\adria\.ai\memory\decisions.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Read the current file to find the next AD number**

```bash
cat "/c/Users/adria/.ai/memory/decisions.md"
```

Find the highest existing `AD-N` and use `N+1` below (the spec deliberately
did not guess this number — read it for real here).

- [ ] **Step 2: Append the new decision entry**

Using the real next number from Step 1 in place of `AD-N` below, append:

```markdown
## AD-N: AI CLI orchestrator biases toward delegation — evolves AD-5, doesn't reverse it (2026-09-16)

**Context:** AD-5 established that nothing in the Claude/Codex/Perplexity
routing convention is automated or auto-dispatched. Adding a local MCP
server (`ai-cli-orchestrator`) that lets Claude Code call Gemini CLI and
GitHub Copilot CLI directly, with a skill that *strongly biases* toward
delegating free/already-paid work rather than doing it in Claude, sits in
tension with AD-5's letter even though it doesn't violate its spirit.

**Decision:** Claude still decides, per turn, whether to delegate — no
tool call happens without that decision. What's new is the *strength* of
the recommendation: the `ai-orchestrator` skill instructs delegating by
default unless the task depends heavily on this session's own
already-loaded context. This is confirmed as an explicit, conscious
evolution of AD-5, not a silent reinterpretation.

**Alternatives considered:** Hard-forced auto-delegation (rejected —
brittle if a backend is down/rate-limited/wrong, and a real reversal of
AD-5 rather than an evolution); leaving Gemini/Copilot entirely outside
the routing convention (rejected — leaves real, free capability unused
for no reason).
```

- [ ] **Step 3: Verify the entry was appended correctly**

```bash
tail -20 "/c/Users/adria/.ai/memory/decisions.md"
```

Expected: the new AD entry is visible at the end of the file, with the
correct next number substituted (not the literal placeholder `AD-N`).

- [ ] **Step 4: Save progress** — check this task's boxes. All tasks complete.

---

## Final check (do this after Task 11, before considering the plan done)

- [ ] Re-run the full test suite one more time from a clean `node_modules`
  state to confirm nothing regressed across tasks:

```bash
cd "/c/Users/adria/.claude/mcp-servers/ai-cli-orchestrator"
rm -rf node_modules
npm install
npm test
```

Expected: all tests across all 6 test files pass, `fail 0`.

- [ ] Confirm `claude mcp list` still shows `ai-cli-orchestrator` connected
  after the `node_modules` reinstall (Step above doesn't require
  re-running `claude mcp add` — the registration points at `index.mjs`,
  which didn't move).
