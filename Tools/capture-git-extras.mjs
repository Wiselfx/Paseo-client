#!/usr/bin/env node
// Captures real daemon traffic for T11 (git extras and live files).
//
// Only touches sandboxes: /tmp/fixture-git (a scratch repo with a local bare remote) and the
// workspaces/projects it creates for that repo. It archives the workspace and removes the
// project before exiting. The scratch checkout is left in place for `paseo-probe git-extras`.
//
// Usage: node Tools/capture-git-extras.mjs <outDir>
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const [outDir = "fixtures-git-extras"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

const ROOT = "/tmp/fixture-git";
const SCRATCH = path.join(ROOT, "scratch-repo");
const REMOTE = path.join(ROOT, "remote.git");
const README = path.join(SCRATCH, "README.md");

fs.mkdirSync(outDir, { recursive: true });
const pending = new Map();
let nextRequest = 0;
let workspaceId = null;
let projectId = null;

const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));

function request(type, fields = {}) {
  const requestId = `t11-${nextRequest++}`;
  const message = { type, requestId, ...fields };
  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject });
    send(message);
  });
}

const save = (name, obj) => {
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
  console.log(`saved ${name}`);
};

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const git = (...args) => execFileSync("git", args, { cwd: SCRATCH, encoding: "utf8" }).trim();

function ensureScratchRepo() {
  fs.mkdirSync(ROOT, { recursive: true });
  if (!fs.existsSync(path.join(REMOTE, "HEAD"))) {
    fs.mkdirSync(REMOTE, { recursive: true });
    execFileSync("git", ["init", "--bare", "-q", "-b", "main", REMOTE]);
  }
  if (!fs.existsSync(path.join(SCRATCH, ".git"))) {
    fs.mkdirSync(SCRATCH, { recursive: true });
    git("init", "-q", "-b", "main");
    git("config", "user.email", "fixture@example.test");
    git("config", "user.name", "Fixture");
    fs.writeFileSync(path.join(SCRATCH, "README.md"), "# scratch\n\nline one\nline two\n");
    fs.writeFileSync(path.join(SCRATCH, "hello.py"), 'print("hello")\n');
    git("add", ".");
    git("commit", "-qm", "initial fixture commit");
    git("remote", "add", "origin", REMOTE);
    git("push", "-qu", "origin", "main");
  }
  if (!git("branch", "--list", "feature/t11")) {
    git("checkout", "-qb", "feature/t11");
    fs.appendFileSync(path.join(SCRATCH, "README.md"), "feature line\n");
    git("commit", "-qam", "feature commit");
    git("push", "-qu", "origin", "feature/t11");
    git("checkout", "-q", "main");
  }
}

ws.onmessage = (event) => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  const inner = message.message ?? message;
  const requestId = inner.payload?.requestId;
  if (requestId && pending.has(requestId)) {
    const { resolve, reject } = pending.get(requestId);
    pending.delete(requestId);
    if (inner.type === "rpc_error") reject(new Error(`${inner.payload.requestType}: ${inner.payload.error}`));
    else resolve(message);
    return;
  }
  if (inner.type === "fs.file.update") {
    save(`fs_file_update_${String(nextFileUpdate++).padStart(2, "0")}`, message);
  }
  if (inner.payload?.status === "server_info") {
    save("server_info", message);
    onReady().catch(async (error) => {
      console.error("capture failed:", error);
      await cleanup();
      ws.close(1000);
      process.exit(1);
    });
  }
};

let nextFileUpdate = 0;

ws.onclose = (event) => {
  if (event.code !== 1000) console.error("closed", event.code, event.reason);
};

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-git-extras",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.1.45",
      capabilities: { helloRejection: true, ownedSubscriptions: true },
      auth,
    }),
  );

async function onReady() {
  ensureScratchRepo();
  // The scratch checkout is tracked by its own local bare remote: no network, no other repo.
  git("checkout", "-q", "main");
  git("reset", "-q", "--hard", "origin/main");

  const created = await request("workspace.create.request", {
    idempotencyKey: `fixture-t11-${Date.now()}`,
    source: { kind: "directory", path: SCRATCH },
  });
  save("workspace_create_response", created);
  const workspace = created.message.payload.workspace;
  if (!workspace) throw new Error(`workspace.create failed: ${created.message.payload.error ?? "unknown"}`);
  workspaceId = workspace.id;
  console.log(`workspace ${workspaceId} cwd=${workspace.workspaceDirectory ?? SCRATCH}`);

  save("checkout_pr_status_response", await request("checkout_pr_status_request", { cwd: SCRATCH }));

  // The daemon advertises newer RPCs one at a time. A daemon without `diff.subscribe.request`
  // answers `rpc_error`; record which side of the fence this one is on.
  try {
    save(
      "diff_subscribe_response",
      await request("diff.subscribe.request", {
        cwd: SCRATCH,
        base: { kind: "rev", rev: "HEAD" },
        head: { kind: "worktree" },
        mergeBase: false,
        highlight: true,
      }),
    );
  } catch (error) {
    save("diff_subscribe_unsupported", { error: String(error) });
  }

  save("branch_suggestions_response", await request("branch_suggestions_request", {
    cwd: SCRATCH,
    query: "feature",
    limit: 20,
  }));

  save("checkout_switch_branch_response", await request("checkout_switch_branch_request", {
    cwd: SCRATCH,
    branch: "feature/t11",
  }));
  await delay(500);
  save("checkout_switch_main_response", await request("checkout_switch_branch_request", {
    cwd: SCRATCH,
    branch: "main",
  }));
  await delay(500);

  fs.appendFileSync(README, "discard me\n");
  await delay(500);
  save("checkout_status_dirty_response", await request("checkout_status_request", { cwd: SCRATCH }));
  save("checkout_discard_changes_response", await request("checkout.discard_changes.request", {
    cwd: SCRATCH,
    paths: ["README.md"],
  }));
  await delay(500);
  save("checkout_status_clean_response", await request("checkout_status_request", { cwd: SCRATCH }));

  const subscribed = await request("fs.file.subscribe.request", {
    cwd: SCRATCH,
    path: "README.md",
  });
  save("fs_file_subscribe_response", subscribed);
  const subscriptionId = subscribed.message.payload.subscriptionId;

  fs.appendFileSync(README, "watched line\n");
  await delay(1200);
  fs.writeFileSync(README, git("show", "HEAD:README.md") + "\n");
  await delay(1200);

  if (subscriptionId) {
    save("fs_file_unsubscribe_response", await request("fs.file.unsubscribe.request", {
      subscriptionId,
    }));
  }

  await cleanup();
  ws.close(1000);
  process.exit(0);
}

async function cleanup() {
  if (workspaceId) {
    try {
      save("archive_workspace_response", await request("archive_workspace_request", { workspaceId }));
    } catch (error) {
      console.error("cleanup archive failed:", error);
    }
    workspaceId = null;
  }
  if (!projectId) {
    try {
      const projects = await request("project.list.request");
      const project = projects.message.payload.projects.find((entry) =>
        entry.projectRootPath === SCRATCH || entry.projectRootPath === ROOT
      );
      projectId = project?.projectId ?? null;
    } catch (error) {
      console.error("cleanup project lookup failed:", error);
    }
  }
  if (projectId) {
    try {
      save("project_remove_response", await request("project.remove.request", { projectId }));
    } catch (error) {
      console.error("cleanup project remove failed:", error);
    }
    projectId = null;
  }
}

setTimeout(() => {
  console.error("capture timed out");
  process.exit(1);
}, 120_000);
