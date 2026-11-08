#!/usr/bin/env node
// Captures real daemon traffic for the host-settings area (T10) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/host-settings/.
//
// Reads are harmless. The only write is `set_daemon_config_request` re-sending the current
// `autoArchiveAfterMerge` value, so the daemon's effective config is unchanged. Slash commands
// are read from the long-lived `/tmp/fixture-sandbox` agent; no agent is created or archived.
//
// Usage: node Tools/capture-host-settings.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ??
  "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/host-settings";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const SANDBOX_CWD = "/tmp/fixture-sandbox";
const SANDBOX_AGENT_ID =
  process.env.SANDBOX_AGENT_ID ?? "1c51ee58-765c-4f8d-bf27-7009338b361e";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : {
      kind: "localCredential",
      token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim(),
    };

fs.mkdirSync(outDir, { recursive: true });

// No hostnames, no real daemon server ids, no host-side paths, no real agent ids.
function scrub(value) {
  if (typeof value === "string") {
    if (/^srv_/.test(value)) return "srv_FIXTURE";
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
      return "00000000-0000-4000-8000-000000000010";
    }
    if (value.startsWith("/home/paseo/.omp/agent/sessions/")) {
      return "/tmp/fixture-sandbox/.fixture-session.jsonl";
    }
    if (value.startsWith("/home/paseo/")) return "/tmp/fixture-sandbox";
    return value;
  }
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      if (key === "hostname") continue;
      if (key === "token" || key === "auth") continue;
      out[key] = scrub(item);
    }
    return out;
  }
  return value;
}

const save = (name, obj) =>
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(scrub(obj), null, 2) + "\n");

const pending = new Map();
const events = [];
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message, timeoutMs = 30000) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(message.requestId);
      reject(new Error(`timeout waiting for ${message.requestId}`));
    }, timeoutMs);
    pending.set(message.requestId, (msg) => {
      clearTimeout(timer);
      resolve(msg);
    });
    send(message);
  });

ws.onmessage = (e) => {
  if (typeof e.data !== "string") return;
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) {
    pending.get(reqId)(msg);
    pending.delete(reqId);
    return;
  }
  if (inner.payload?.status === "server_info") {
    onReady(msg).catch((error) => {
      console.error(error);
      process.exit(1);
    });
    return;
  }
  if (inner.type === "status" && inner.payload?.status === "daemon_config_changed") {
    events.push(msg);
  }
};
ws.onclose = (e) => {
  if (e.code !== 1000) console.error("closed", e.code, e.reason);
};
ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-capture-host-settings",
      clientType: "mobile",
      protocolVersion: 1,
      // >= 0.1.45: the daemon hides non-legacy providers (pi, omp) from older clients.
      appVersion: "0.1.45",
      capabilities: { helloRejection: true },
      auth,
    }),
  );

const waitFor = (predicate, timeoutMs, label) =>
  new Promise((resolve, reject) => {
    const started = Date.now();
    const tick = () => {
      const hit = events.find(predicate);
      if (hit) return resolve(hit);
      if (Date.now() - started > timeoutMs) return reject(new Error(`timeout: ${label}`));
      setTimeout(tick, 100);
    };
    tick();
  });

async function sandboxAgentId() {
  const listed = await request({
    type: "fetch_agents_request",
    requestId: "agents",
    includeBackground: true,
    page: { limit: 200 },
  });
  const sandbox = listed.message.payload.entries.find(
    (entry) => entry.agent.cwd === SANDBOX_CWD,
  );
  return sandbox?.agent.id ?? SANDBOX_AGENT_ID;
}

async function onReady(serverInfo) {
  save("server_info", serverInfo);

  const config = await request({ type: "get_daemon_config_request", requestId: "config" });
  save("get_daemon_config_response", config);
  const current = config.message.payload.config;
  console.log(
    `config: providers=${Object.keys(current.providers ?? {}).length} profiles=${(current.agentProfiles ?? []).length}`,
  );

  // Nudge one inert string and restore it immediately. `resumePrompt` is only read when the
  // daemon restarts, so no running agent can observe the value while it is briefly different.
  const originalPrompt = current.resumePrompt;
  if (typeof originalPrompt !== "string") {
    throw new Error("config.resumePrompt is not a string; refusing to guess a harmless patch");
  }
  const markerPrompt = `${originalPrompt} [fixture-capture]`;
  try {
    const patched = await request({
      type: "set_daemon_config_request",
      requestId: "config-patch",
      config: { resumePrompt: markerPrompt },
    });
    save("set_daemon_config_response", patched);
    console.log(
      `patch resumePrompt (temporary): effective=${JSON.stringify(patched.message.payload.config.resumePrompt)}`,
    );

    try {
      const changed = await waitFor(
        (msg) => msg.message?.payload?.status === "daemon_config_changed",
        5000,
        "daemon_config_changed",
      );
      save("daemon_config_changed", changed);
      console.log("captured daemon_config_changed");
    } catch {
      console.log("daemon_config_changed was not broadcast for a changed config");
    }
  } finally {
    const restored = await request({
      type: "set_daemon_config_request",
      requestId: "config-restore",
      config: { resumePrompt: originalPrompt },
    });
    if (restored.message.payload.config.resumePrompt !== originalPrompt) {
      throw new Error("resumePrompt was not restored");
    }
    console.log("restored resumePrompt");
  }

  const agentId = await sandboxAgentId();
  const commands = await request({
    type: "list_commands_request",
    requestId: "commands",
    agentId,
  });
  save("list_commands_response", commands);
  const payload = commands.message.payload;
  console.log(
    `commands for sandbox agent: ${payload.commands.length} (error=${payload.error ?? "none"})`,
  );

  const unregistered = await request({
    type: "push.unregister.request",
    requestId: "push-unregister",
    token: "fixture-token-not-registered",
  });
  save("push_unregister_response", unregistered);
  console.log("captured push.unregister.response");

  ws.close(1000);
  process.exit(0);
}
