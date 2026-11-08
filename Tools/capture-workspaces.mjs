#!/usr/bin/env node
// Captures real daemon traffic for T7 (workspaces, git, diffs, files) as JSON fixtures.
//
// Only touches sandboxes: the registered /tmp/fixture-sandbox checkout, new directories under
// /tmp/fixture-git (a scratch repo with a local bare remote), and workspaces it creates itself.
// It archives the worktree workspace and removes the project it added before exiting.
//
// Usage: node Tools/capture-workspaces.mjs <outDir>
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures may contain prompts and file paths. Review before committing.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const [outDir = "fixtures-workspaces"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

const SANDBOX = "/tmp/fixture-sandbox";
let createdWorkspaceId = null;
const SCRATCH = "/tmp/fixture-git/scratch-repo";
const NEW_PROJECT = "/tmp/fixture-git/new-project";

fs.mkdirSync(outDir, { recursive: true });
const pending = new Map();
const savedEvents = new Map();
let nextRequest = 0;

const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));

function request(type, fields = {}) {
  const requestId = `t7-${nextRequest++}`;
  const message = { type, requestId, ...fields };
  return new Promise((resolve) => {
    pending.set(requestId, resolve);
    send(message);
  });
}

const save = (name, obj) => {
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
  console.log(`saved ${name}`);
};

const saveEvent = (name, obj, limit = 3) => {
  const count = savedEvents.get(name) ?? 0;
  if (count >= limit) return;
  savedEvents.set(name, count + 1);
  save(`${name}_${String(count).padStart(2, "0")}`, obj);
};

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

ws.onmessage = (event) => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  const inner = message.message ?? message;
  const requestId = inner.payload?.requestId;
  if (requestId && pending.has(requestId)) {
    pending.get(requestId)(message);
    pending.delete(requestId);
    return;
  }
  if (inner.payload?.status === "server_info") {
    save("server_info", message);
    onReady().catch((error) => {
      console.error("capture failed:", error);
      ws.close(1000);
      process.exit(1);
    });
    return;
  }
  if (["workspace_update", "project.update", "checkout_status_update", "checkout_diff_update"].includes(inner.type)) {
    // The git observer also pushes status for workspaces this capture does not own.
    if (inner.type === "checkout_status_update") {
      const cwd = inner.payload?.cwd ?? "";
      if (!cwd.startsWith("/tmp/fixture-sandbox") && !cwd.includes("/fixture-t7")) return;
    }
    if (inner.type === "workspace_update") {
      const id = inner.payload?.workspace?.id ?? inner.payload?.id;
      if (id !== createdWorkspaceId && id !== "wks_6adc97aa7e1e49e3") return;
    }
    saveEvent(inner.type.replaceAll(".", "_"), message);
  }
};

ws.onclose = (event) => {
  if (event.code !== 1000) console.error("closed", event.code, event.reason);
};

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-workspaces",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.0.1",
      capabilities: { helloRejection: true },
      auth,
    }),
  );

async function onReady() {
  const events = await request("session.events.set_subscription.request", {
    events: ["project.update", "checkout_status_update"],
  });
  save("session_events_set_subscription_response", events);

  const projects = await request("project.list.request");
  save("project_list_response", projects);

  const workspaces = await request("fetch_workspaces_request", {
    includeBackground: true,
    subscribe: {},
  });
  save("fetch_workspaces_response", workspaces);

  const entries = workspaces.message.payload.entries;
  const sandbox = entries.find((entry) => entry.projectRootPath === SANDBOX) ?? entries[0];
  if (!sandbox) throw new Error("no workspace to capture against");
  const cwd = sandbox.workspaceDirectory ?? sandbox.projectRootPath;

  save("checkout_status_response", await request("checkout_status_request", { cwd }));

  const diff = await request("subscribe_checkout_diff_request", {
    cwd,
    compare: { mode: "uncommitted" },
  });
  save("subscribe_checkout_diff_response", diff);
  const subscriptionId = diff.message.payload.subscriptionId;

  // Make one more edit while subscribed so the daemon pushes a real `checkout_diff_update`.
  const readmePath = path.join(SANDBOX, "README.md");
  const readme = fs.readFileSync(readmePath, "utf8");
  fs.writeFileSync(readmePath, readme + "\nfixture diff update\n");
  await delay(1200);
  fs.writeFileSync(readmePath, readme);

  save("checkout_diff_get_response", await request("checkout.diff.get.request", {
    cwd,
    compare: { mode: "uncommitted" },
  }));

  save("file_explorer_list_response", await request("file_explorer_request", {
    cwd,
    path: ".",
    mode: "list",
  }));
  save("file_explorer_file_response", await request("file_explorer_request", {
    cwd,
    path: "convert.py",
    mode: "file",
    maxBytes: 4096,
  }));

  const branchName = `fixture-t7-worktree-${Date.now()}`;
  const workspaceId = "wks_" + crypto.randomBytes(8).toString("hex");
  const created = await request("workspace.create.request", {
    workspaceId,
    idempotencyKey: `fixture-t7-${Date.now()}`,
    source: {
      kind: "worktree",
      cwd,
      action: "branch-off",
      refName: "refs/heads/main",
      branchName,
      worktreeSlug: "fixture-t7",
    },
  });
  save("workspace_create_response", created);
  const createdWorkspace = created.message.payload.workspace;
  createdWorkspaceId = createdWorkspace?.id ?? null;
  if (!createdWorkspace) throw new Error(`workspace.create failed: ${created.message.payload.error ?? "unknown"}`);
  await delay(1000);

  if (createdWorkspace?.workspaceDirectory) {
    // Dirty the fresh worktree so the git observer pushes a real checkout_status_update.
    fs.writeFileSync(path.join(createdWorkspace.workspaceDirectory, "fixture-status.txt"), "status fixture\n");
    await delay(1500);
  }

  if (createdWorkspace) {
    save("workspace_title_set_response", await request("workspace.title.set.request", {
      workspaceId: createdWorkspace.id,
      title: "Fixture T7 worktree",
    }));
    save("workspace_title_reset_response", await request("workspace.title.set.request", {
      workspaceId: createdWorkspace.id,
      title: null,
    }));
    save("archive_workspace_response", await request("archive_workspace_request", {
      workspaceId: createdWorkspace.id,
    }));
    await delay(1000);
  }

  if (subscriptionId) {
    save("subscription_release_response", await request("subscription.release.request", {
      subscriptionId,
    }));
  }

  const added = await request("project.add.request", { cwd: NEW_PROJECT });
  save("project_add_response", added);
  const addedProject = added.message.payload.project;
  if (addedProject) {
    save("project_remove_response", await request("project.remove.request", {
      projectId: addedProject.projectId,
    }));
  }

  fs.appendFileSync(path.join(SCRATCH, "hello.py"), "\nprint('fixture change')\n");
  save("scratch_checkout_status_response", await request("checkout_status_request", { cwd: SCRATCH }));
  save("checkout_commit_response", await request("checkout_commit_request", {
    cwd: SCRATCH,
    message: "Fixture: commit from capture",
    addAll: true,
  }));
  save("checkout_push_response", await request("checkout_push_request", { cwd: SCRATCH }));

  save("github_search_repositories_response", await request("workspace.github.search_repositories.request", {
    query: "paseo",
    limit: 5,
  }));

  console.log(`events: ${[...savedEvents.entries()].map(([name, count]) => `${name}=${count}`).join(" ") || "none"}`);
  sanitize();
  ws.close(1000);
  process.exit(0);
}

// Keeps only fixtures for sandboxes we own and strips host identity, home paths and workspace
// ids that did not come from this capture.
function sanitize() {
  const files = fs.readdirSync(outDir).filter((name) => name.endsWith(".json"));
  const messages = new Map();
  for (const name of files) {
    messages.set(name, JSON.parse(fs.readFileSync(path.join(outDir, name), "utf8")));
  }

  // Drop other people's rows before collecting the ids this capture owns.
  for (const message of messages.values()) {
    const payload = message.message?.payload;
    if (Array.isArray(payload?.entries)) {
      payload.entries = payload.entries.filter(
        (entry) => entry.name === "fixture sandbox" && entry.projectRootPath === "/tmp/fixture-sandbox",
      );
    }
    if (Array.isArray(payload?.emptyProjects)) {
      payload.emptyProjects = payload.emptyProjects.filter(
        (project) => project.projectRootPath === "/tmp/fixture-sandbox",
      );
    }
    if (Array.isArray(payload?.projects)) {
      payload.projects = payload.projects.filter((project) => project.projectRootPath === "/tmp/fixture-sandbox");
    }
  }

  const allowedWorkspaces = new Set();
  const allowedProjects = new Set();
  const collect = (value) => {
    if (Array.isArray(value)) return value.forEach(collect);
    if (!value || typeof value !== "object") return;
    if (typeof value.id === "string" && value.id.startsWith("wks_")) allowedWorkspaces.add(value.id);
    if (typeof value.workspaceId === "string" && value.workspaceId.startsWith("wks_")) {
      allowedWorkspaces.add(value.workspaceId);
    }
    if (typeof value.projectId === "string" && value.projectId.startsWith("prj_")) {
      allowedProjects.add(value.projectId);
    }
    for (const child of Object.values(value)) collect(child);
  };
  for (const message of messages.values()) collect(message);

  const scrubString = (value) =>
    value
      .replace(/srv_[A-Za-z0-9]+/g, "srv_FIXTURE")
      .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g, "00000000-0000-0000-0000-000000000000")
      .replace(/\/home\/paseo\/\.paseo\/worktrees\/[A-Za-z0-9]+/g, "/tmp/fixture-home/.paseo/worktrees/fixture-wt")
      .replace(/\/home\/paseo/g, "/tmp/fixture-home")
      .replace(/wks_[a-f0-9]{16}/g, (match) => (allowedWorkspaces.has(match) ? match : "wks_FIXTURE00000000"))
      .replace(/prj_[a-f0-9]{16}/g, (match) => (allowedProjects.has(match) ? match : "prj_FIXTURE00000000"));

  const scrub = (value, key) => {
    if (typeof value === "string") return key === "hostname" ? "fixture-host" : scrubString(value);
    if (Array.isArray(value)) return value.map((item) => scrub(item));
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.entries(value).map(([childKey, child]) => [childKey, scrub(child, childKey)]));
    }
    return value;
  };

  for (const [name, message] of messages) {
    fs.writeFileSync(path.join(outDir, name), JSON.stringify(scrub(message), null, 2) + "\n");
  }
  console.log("sanitized fixtures");
}

setTimeout(() => {
  console.error("capture timed out");
  process.exit(1);
}, 120_000);
