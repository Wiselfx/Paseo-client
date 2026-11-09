#!/usr/bin/env node
// Captures real daemon traffic for the fork feature (M7h) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/fork/.
//
// Creates ONE throwaway agent in /tmp/fixture-sandbox (provider opencode, prompt
// "M7h fork probe: reply with exactly READY and nothing else."), waits for the turn,
// forks it at the READY message, then archives both the source and the forked agent.
// Nothing else in the sandbox is touched.
//
// Usage: node Tools/capture-fork.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures contain the prompt text and the forked chat-history text; review before committing.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ?? "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/fork";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const SANDBOX_CWD = "/tmp/fixture-sandbox";
const PROVIDER = "opencode";
const PROMPT = "M7h fork probe: reply with exactly READY and nothing else.";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : {
      kind: "localCredential",
      token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim(),
    };

fs.mkdirSync(outDir, { recursive: true });

// No hostnames, no server ids, no host paths, and deterministic throwaway ids.
const ID_MAP = new Map();
function scrubString(value) {
  if (/^srv_/.test(value)) return "srv_FIXTURE";
  if (value.startsWith("/home/paseo/")) return "/tmp/fixture-sandbox";
  return value;
}
function scrub(value) {
  if (typeof value === "string") {
    // Deterministically map uuid-like agent/workspace/message ids to stable placeholders.
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (uuid.test(value) && !ID_MAP.has(value)) {
      ID_MAP.set(value, `fork-fixture-${ID_MAP.size + 1}`);
    }
    if (ID_MAP.has(value)) return ID_MAP.get(value);
    return scrubString(value);
  }
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      if (key === "hostname") { out[key] = "fixture-host"; continue; }
      if (key === "serverId") { out[key] = "srv_FIXTURE"; continue; }
      out[key] = scrub(item);
    }
    return out;
  }
  return value;
}

const save = (name, obj) =>
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(scrub(obj), null, 2) + "\n");

const ws = new WebSocket(url);
const send = (m) => ws.send(JSON.stringify({ type: "session", message: m }));
const pending = new Map();
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  if (inner?.payload?.status === "server_info") {
    save("server_info", msg);
    onHello().catch((error) => { console.error("capture failed:", error); ws.close(1000); process.exit(1); });
    return;
  }
  const reqId = inner?.payload?.requestId ?? inner?.requestId;
  if (reqId && pending.has(reqId)) {
    pending.get(reqId)(inner);
    pending.delete(reqId);
  }
};
const ws_request = (m) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout ${m.requestId}`)), 180000);
    pending.set(m.requestId, (inner) => { clearTimeout(timer); resolve(inner); });
    send(m);
  });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

ws.onclose = (e) => { if (e.code !== 1000) console.error("closed", e.code, e.reason); };
ws.onopen = () =>
  ws.send(JSON.stringify({
    type: "hello", clientId: "fixture-capture-fork", clientType: "mobile", protocolVersion: 1,
    appVersion: "0.0.1", capabilities: { helloRejection: true }, auth,
  }));

async function onHello() {
  console.log("connected; creating one throwaway agent in", SANDBOX_CWD);

  const created = await ws_request({
    type: "create_agent_request",
    requestId: "fork-create-source",
    config: { provider: PROVIDER, cwd: SANDBOX_CWD },
    initialPrompt: PROMPT,
    labels: {},
  });
  const sourceAgent = created?.payload?.agent ?? created?.agent ?? null;
  const sourceId = created?.payload?.agentId ?? sourceAgent?.id ?? null;
  if (!sourceId) throw new Error("agent not created: " + JSON.stringify(created?.payload ?? created));
  save("create_agent_response", { type: "session", message: created });
  console.log("source agent:", sourceId);

  const wait = await ws_request({
    type: "wait_for_finish_request", agentId: sourceId, timeoutMs: 120000,
    requestId: "fork-wait",
  });
  console.log("wait status:", wait?.payload?.status);

  const timeline = await ws_request({
    type: "fetch_agent_timeline_request",
    agentId: sourceId, direction: "tail", limit: 10, projection: "projected", wholeTurns: true,
    requestId: "fork-timeline",
  });
  save("fork_timeline_page", { type: "session", message: timeline });
  const entries = timeline?.payload?.entries ?? [];
  const target = entries.find(
    (e) => e.item?.type === "user_message" && (e.item?.text ?? "").includes("M7h fork probe"),
  );
  if (!target) throw new Error("probe message not found");
  const epoch = timeline?.payload?.epoch;
  const boundarySeq = target.seqEnd;
  console.log("forking at seq", boundarySeq, "epoch", epoch);

  const fork = await ws_request({
    type: "agent.fork_context.request", agentId: sourceId,
    boundaryCursor: { epoch, seq: boundarySeq },
    requestId: "fork-context",
  });
  if (fork?.payload?.error) throw new Error("fork failed: " + fork.payload.error);
  save("agent_fork_context_response", { type: "session", message: fork });
  const forkAttachment = fork?.payload?.attachment ?? null;
  console.log("fork attachment items:", fork?.payload?.itemCount, "chars:", forkAttachment?.text?.length ?? 0);

  const forkCreated = await ws_request({
    type: "create_agent_request",
    requestId: "fork-create-child",
    config: { provider: PROVIDER, cwd: SANDBOX_CWD },
    attachments: forkAttachment ? [forkAttachment] : [],
    labels: {},
  });
  save("create_fork_response", { type: "session", message: forkCreated });
  const forkId = forkCreated?.payload?.agentId ?? forkCreated?.payload?.agent?.id ?? null;
  console.log("forked agent:", forkId);

  for (const [name, id] of [["source", sourceId], ["fork", forkId]]) {
    if (!id) continue;
    await ws_request({ type: "archive_agent_request", agentId: id, requestId: `archive-${name}` })
      .catch((e) => console.error("archive", name, "failed:", e));
    console.log("archived", name);
  }
  console.log("fixtures in", outDir);
  ws.close(1000);
  process.exit(0);
}
