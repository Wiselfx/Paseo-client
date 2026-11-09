#!/usr/bin/env node
// Captures real daemon traffic for M2.11 (project settings) as JSON fixtures.
//
// Only touches the registered /tmp/fixture-sandbox checkout: one read_project_config_request
// (before), one write_project_config_request (creates /tmp/fixture-sandbox/paseo.json with a
// fixture-only config), one read (after), and one project.icon.get.request. The paseo.json is
// deleted afterwards so the sandbox returns to its prior state (no paseo.json).
//
// Usage: node Tools/capture-project-config.mjs <outDir>
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixture paths/ids are scrubbed after capture (repoRoot -> /fixture-sandbox, ids -> *_FIXTURE).
import fs from "node:fs";
import path from "node:path";

const [outDir = "fixtures-project-config"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

const SANDBOX = "/tmp/fixture-sandbox";
const SANDBOX_BASENAME = path.basename(SANDBOX);
const FIXTURE_CONFIG = {
  worktree: {
    setup: ["echo fixture-setup-ran"],
    teardown: ["echo fixture-teardown-ran"],
  },
  scripts: {
    "fixture-script": { type: "service", command: "echo fixture-script-ran", port: 4173 },
  },
};

fs.mkdirSync(outDir, { recursive: true });
const pending = new Map();
let nextRequest = 0;
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));

function request(type, fields = {}) {
  const requestId = `m211-${nextRequest++}`;
  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject });
    send({ type, requestId, ...fields });
  });
}

const save = (name, obj) => {
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
  console.log(`saved ${name}`);
};

ws.onmessage = (event) => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  const inner = message.message ?? message;
  const requestId = inner.payload?.requestId;
  if (requestId && pending.has(requestId)) {
    const { resolve, reject } = pending.get(requestId);
    pending.delete(requestId);
    const rpcError = inner.type === "rpc_error";
    if (rpcError) reject(new Error(`${inner.payload.requestType}: ${inner.payload.error}`));
    else resolve(message);
    return;
  }
  if (inner.payload?.status === "server_info") {
    main().catch((error) => {
      console.error("capture failed:", error);
      cleanup();
      ws.close(1000);
      process.exit(1);
    });
  }
};

function cleanup() {
  if (fs.existsSync(path.join(SANDBOX, "paseo.json"))) {
    fs.unlinkSync(path.join(SANDBOX, "paseo.json"));
    console.log("restored: deleted /tmp/fixture-sandbox/paseo.json");
  }
}

async function main() {
  // Read the current (absent) config.
  const before = await request("read_project_config_request", { repoRoot: SANDBOX });
  save("project_config_read_response", before);
  const revision = before.message.payload.revision ?? null;

  // Write the fixture config with optimistic concurrency.
  const written = await request("write_project_config_request", {
    repoRoot: SANDBOX,
    config: FIXTURE_CONFIG,
    expectedRevision: revision,
  });
  save("project_config_write_response", written);

  // Read it back (config + revision non-null now).
  const after = await request("read_project_config_request", { repoRoot: SANDBOX });
  save("project_config_read_after_write_response", after);

  // Icon get is read-only; find the sandbox project id from the registry in memory.
  const projects = await request("project.list.request", {});
  const list = projects.message?.payload?.projects ?? [];
  const sandbox = list.find((p) => typeof p.projectRootPath === "string" && p.projectRootPath.endsWith(SANDBOX_BASENAME));
  if (sandbox?.projectId) {
    const icon = await request("project.icon.get.request", { projectId: sandbox.projectId });
    save("project_icon_get_response", icon);
  } else {
    console.log("sandbox project not found in project.list; skipping icon capture");
  }

  cleanup();
  ws.close(1000);
  process.exit(0);
}

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "capture-project-config",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.1.45",
      capabilities: { helloRejection: true },
      auth,
    }),
  );
ws.onclose = (event) => { if (event.code !== 1000) console.error("closed", event.code, event.reason); };
ws.onerror = (event) => { console.error("ws error", event); process.exit(1); };
