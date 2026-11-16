#!/usr/bin/env node
// Captures the workspace-mutations fixtures from the live daemon, on sandboxes only.
// Creates /tmp/fixture-mutations, adds it as a project, renames it, clears the rename, pins and
// unpins the /tmp/fixture-sandbox workspace, sets its base branch to the ref it already uses
// (refs/heads/main, idempotent), and removes the throwaway project afterwards.
// Never run this against workspaces or projects you didn't create.
// Usage: node Tools/capture-mutations.mjs
import fs from "node:fs";
import path from "node:path";

const outDir = "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/workspaces";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };
const sandboxDir = "/tmp/fixture-sandbox";
const mutationsDir = "/tmp/fixture-mutations";

fs.mkdirSync(mutationsDir, { recursive: true });
fs.writeFileSync(path.join(mutationsDir, "README.md"), "# fixture mutations\n");

const save = (name, obj) => fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
const pending = new Map();
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) =>
  new Promise((resolve) => { pending.set(message.requestId, resolve); send(message); });

let sandboxId = null;

ws.onmessage = (e) => {
  if (typeof e.data !== "string") return;
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) { pending.get(reqId)(msg); pending.delete(reqId); return; }
  if (inner.payload?.status === "server_info") { onReady(); }
};
ws.onopen = () => ws.send(JSON.stringify({
  type: "hello", clientId: "fixture-capture", clientType: "mobile", protocolVersion: 1,
  appVersion: "0.1.45", capabilities: { helloRejection: true }, auth,
}));

async function onReady() {
  try {
    const sandboxes = await request({ type: "fetch_workspaces_request", requestId: "find-sandbox", includeBackground: true });
    const entries = sandboxes.message.payload.entries.filter(
      (w) => w.workspaceDirectory === sandboxDir || w.projectRootPath === sandboxDir,
    );
    const sandbox = entries.find((w) => w.name === "fixture sandbox") ?? entries[0];
    if (!sandbox) { console.error("sandbox workspace not found"); process.exit(1); }
    sandboxId = sandbox.id;
    console.log("sandbox workspace", sandboxId);

    const added = await request({ type: "project.add.request", requestId: "add-mutations", cwd: mutationsDir });
    const projectId = added.message.payload.project?.projectId;
    if (!projectId) { console.error("project.add failed", JSON.stringify(added)); process.exit(1); }
    console.log("added project", projectId);

    save("project_rename_response", await request({
      type: "project.rename.request", requestId: "rename-mutations", projectId, customName: "Mutation fixture",
    }));
    save("project_rename_clear_response", await request({
      type: "project.rename.request", requestId: "rename-mutations-clear", projectId, customName: null,
    }));
    save("workspace_pin_set_response", await request({
      type: "workspace.pin.set.request", requestId: "pin-sandbox", workspaceId: sandboxId, pinned: true,
    }));
    save("workspace_pin_set_unpin_response", await request({
      type: "workspace.pin.set.request", requestId: "unpin-sandbox", workspaceId: sandboxId, pinned: false,
    }));
    save("workspace_base_branch_set_response", await request({
      type: "workspace.base_branch.set.request", requestId: "base-sandbox", workspaceId: sandboxId,
      baseRef: "refs/heads/main",
    }));

    const removed = await request({ type: "project.remove.request", requestId: "remove-mutations", projectId });
    console.log("removed project:", removed.message.payload?.accepted);

    console.log("done");
    ws.close(1000);
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}
