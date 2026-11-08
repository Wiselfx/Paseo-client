#!/usr/bin/env node
// Captures real daemon traffic for the agent-control area (T6) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/agent-control/.
//
// Only ever touches /tmp/fixture-sandbox: it creates one omp agent there in mode "ask",
// answers one permission request with allow and one with deny, changes mode/model/thinking,
// renames, clears attention and archives it. Nothing else is created, killed or archived.
//
// Usage: node Tools/capture-agent-control.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures may contain the prompt text used below; review before committing.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ??
  "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/agent-control";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const SANDBOX_CWD = "/tmp/fixture-sandbox";
const PROVIDER = "omp";
const MODEL = "opencode-go/deepseek-v4.1-flash";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : {
      kind: "localCredential",
      token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim(),
    };

fs.mkdirSync(outDir, { recursive: true });

// No hostnames, no daemon server ids, no host-side session paths. The agent ids kept are the
// sandbox agents this script created.
function scrub(value) {
  if (typeof value === "string") {
    if (/^srv_/.test(value)) return "srv_FIXTURE";
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
let createdAgentId = null;
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

// The daemon broadcasts events; keep the ones this area cares about.
const KEEP = new Set([
  "agent_permission_request",
  "agent_permission_resolved",
  "agent_attention_required",
  "agent_update",
  "agent_archived",
]);

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
    // Never leave a sandbox agent behind, even when a capture step fails.
    onReady(msg).catch(async (error) => {
      console.error(error);
      if (createdAgentId) {
        await request({
          type: "archive_agent_request",
          requestId: "cleanup-archive",
          agentId: createdAgentId,
        }).catch(() => {});
        console.error(`archived ${createdAgentId} after failure`);
      }
      process.exit(1);
    });
    return;
  }
  if (inner.type && KEEP.has(inner.type)) {
    events.push(msg);
    if (
      inner.type === "agent_update" &&
      inner.payload?.kind === "upsert" &&
      inner.payload.agent?.id === createdAgentId
    ) {
      if (inner.payload.agent.title === "T6 probe agent") save("agent_update_renamed", msg);
      else save("agent_update_created", msg);
    }
    if (inner.type === "agent_permission_request") {
      const kind = `permission_request_${inner.payload.request.kind}`;
      if (!fs.existsSync(path.join(outDir, kind + ".json"))) save(kind, msg);
    }
    if (inner.type === "agent_permission_resolved") {
      const behavior = inner.payload.resolution?.behavior ?? "unknown";
      if (!fs.existsSync(path.join(outDir, `permission_resolved_${behavior}.json`))) {
        save(`permission_resolved_${behavior}`, msg);
      }
    }
    if (inner.type === "agent_attention_required") {
      save("agent_attention_required", msg);
    }
    if (inner.type === "agent_archived") save("agent_archived", msg);
  }
};
ws.onclose = (e) => {
  if (e.code !== 1000) console.error("closed", e.code, e.reason);
};
ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-capture-agent-control",
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

async function onReady(serverInfo) {
  save("server_info", serverInfo);

  // Subscribing is what makes the daemon push live `agent_update` rows (create, rename, archive).
  await request({
    type: "fetch_agents_request",
    requestId: "agents",
    includeBackground: true,
    page: { limit: 50 },
    subscribe: {},
  });

  const snapshot = await request({ type: "get_providers_snapshot_request", requestId: "snapshot" });
  save("providers_snapshot_response", snapshot);
  const omp = snapshot.message.payload.entries.find((entry) => entry.provider === PROVIDER);
  if (!omp) throw new Error(`${PROVIDER} missing from the provider snapshot`);
  const modes = omp.modes ?? [];
  const ask = modes.find((mode) => mode.id === "ask") ?? modes[0];
  if (!ask) throw new Error(`${PROVIDER} has no modes`);
  console.log(`providers: ${snapshot.message.payload.entries.map((e) => e.provider).join(", ")}`);
  console.log(`${PROVIDER} modes: ${modes.map((m) => `${m.id} (${m.label})`).join(", ")}`);

  const models = await request({
    type: "list_provider_models_request",
    requestId: "models",
    provider: PROVIDER,
    cwd: SANDBOX_CWD,
  });
  save("list_provider_models_response", models);
  const modesResponse = await request({
    type: "list_provider_modes_request",
    requestId: "modes",
    provider: PROVIDER,
    cwd: SANDBOX_CWD,
  });
  save("list_provider_modes_response", modesResponse);

  const created = await request({
    type: "create_agent_request",
    requestId: "create",
    config: { provider: PROVIDER, cwd: SANDBOX_CWD, modeId: ask.id, model: MODEL },
    initialPrompt: "Reply with the single word: ready",
    labels: { "paseo.fixture": "t6-agent-control" },
  });
  save("create_agent_response", created);
  createdAgentId = created.message.payload.agentId;
  if (!createdAgentId) throw new Error(`create failed: ${created.message.payload.error}`);
  console.log(`created ${createdAgentId} in ${SANDBOX_CWD} (mode ${ask.id})`);
  const listed = await request({
    type: "fetch_agents_request",
    requestId: "agents-created",
    includeBackground: true,
    page: { limit: 50 },
  });
  listed.message.payload.entries = listed.message.payload.entries.filter(
    (entry) => entry.agent.id === createdAgentId,
  );
  save("fetch_agents_response", listed);

  // Let the first turn settle so mode changes apply to a quiet agent.
  await new Promise((resolve) => setTimeout(resolve, 2500));

  const setMode = await request({
    type: "set_agent_mode_request",
    requestId: "mode",
    agentId: createdAgentId,
    modeId: "write",
  });
  save("set_agent_mode_response", setMode);
  console.log(`mode -> write: accepted=${setMode.message.payload.accepted}`);
  await new Promise((resolve) => setTimeout(resolve, 1000));

  const setThinking = await request({
    type: "set_agent_thinking_request",
    requestId: "thinking",
    agentId: createdAgentId,
    thinkingOptionId: "low",
  });
  save("set_agent_thinking_response", setThinking);
  console.log(`thinking -> low: accepted=${setThinking.message.payload.accepted}`);

  const setModel = await request({
    type: "set_agent_model_request",
    requestId: "model",
    agentId: createdAgentId,
    modelId: MODEL,
  });
  save("set_agent_model_response", setModel);
  console.log(`model -> ${MODEL}: accepted=${setModel.message.payload.accepted}`);

  // Back to "ask" so a shell command parks on a permission request.
  await request({
    type: "set_agent_mode_request",
    requestId: "mode-ask",
    agentId: createdAgentId,
    modeId: ask.id,
  });
  await new Promise((resolve) => setTimeout(resolve, 500));

  const allowRequest = await triggerPermission("echo t6-allow", "allow");
  save("fetch_agent_with_pending_permission_response", allowRequest.snapshot);
  console.log(
    `permission pending: kind=${allowRequest.request.kind} title=${allowRequest.request.title ?? "-"} actions=${(allowRequest.request.actions ?? []).map((a) => `${a.id}:${a.behavior}`).join(",")}`,
  );
  send({
    type: "agent_permission_response",
    agentId: createdAgentId,
    requestId: allowRequest.request.id,
    response: { behavior: "allow" },
  });
  await waitFor(
    (msg) =>
      msg.message?.type === "agent_permission_resolved" &&
      msg.message.payload.requestId === allowRequest.request.id,
    15000,
    "permission resolved (allow)",
  );
  console.log("answered allow");

  await new Promise((resolve) => setTimeout(resolve, 2500));

  const denyRequest = await triggerPermission("echo t6-deny", "deny");
  send({
    type: "agent_permission_response",
    agentId: createdAgentId,
    requestId: denyRequest.request.id,
    response: { behavior: "deny", message: "Denied by fixture capture" },
  });
  await waitFor(
    (msg) =>
      msg.message?.type === "agent_permission_resolved" &&
      msg.message.payload.requestId === denyRequest.request.id,
    15000,
    "permission resolved (deny)",
  );
  console.log("answered deny");

  const renamed = await request({
    type: "update_agent_request",
    requestId: "rename",
    agentId: createdAgentId,
    name: "T6 probe agent",
  });
  save("update_agent_response", renamed);
  console.log(`rename: accepted=${renamed.message.payload.accepted}`);

  const cleared = await request({
    type: "clear_agent_attention",
    requestId: "clear-attention",
    agentId: createdAgentId,
  });
  save("clear_agent_attention_response", cleared);
  console.log(`clear attention: agents=${cleared.message.payload.agents?.length ?? 0}`);

  const archived = await request({
    type: "archive_agent_request",
    requestId: "archive",
    agentId: createdAgentId,
  });
  save("archive_agent_response", archived);
  console.log(`archived ${createdAgentId}`);
  await new Promise((resolve) => setTimeout(resolve, 500));
  ws.close(1000);
  process.exit(0);
}

/** Sends a shell prompt and waits until a permission request for it arrives. */
async function triggerPermission(command, label) {
  const before = new Set(
    events
      .filter((m) => m.message?.type === "agent_permission_request")
      .map((m) => m.message.payload.request.id),
  );
  await request({
    type: "send_agent_message_request",
    requestId: `prompt-${label}`,
    agentId: createdAgentId,
    text: `Use the shell tool to run exactly: ${command}`,
    messageId: `fixture-${label}-message`,
  });
  const message = await waitFor(
    (msg) =>
      msg.message?.type === "agent_permission_request" &&
      msg.message.payload.agentId === createdAgentId &&
      !before.has(msg.message.payload.request.id),
    60000,
    `permission request (${label})`,
  );
  const snapshot = await request({
    type: "fetch_agent_request",
    requestId: `fetch-${label}`,
    agentId: createdAgentId,
  });
  return { request: message.message.payload.request, snapshot };
}
