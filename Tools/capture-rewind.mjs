#!/usr/bin/env node
// Captures real daemon traffic for the rewind area (M7d) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/rewind/.
//
// Only ever touches the fixture sandbox agent 1c51ee58-765c-4f8d-bf27-7009338b361e: it sends one
// disposable message, waits for the turn to settle, then performs one conversation-mode rewind
// to that very message — the smallest lossless rewind. The agent's other rows are untouched.
//
// Usage: node Tools/capture-rewind.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures may contain the prompt text used below; review before committing.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ??
  "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/rewind";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const AGENT_ID = "1c51ee58-765c-4f8d-bf27-7009338b361e";
const PROMPT = "M7d rewind probe: reply with exactly READY and nothing else.";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : {
      kind: "localCredential",
      token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim(),
    };

fs.mkdirSync(outDir, { recursive: true });

// No hostnames, no daemon server ids, no host-side session paths.
function scrub(value) {
  if (typeof value === "string") {
    if (/^srv_/.test(value)) return "srv_FIXTURE";
    // Substitute any host-side path segment, not just leading prefixes.
    if (value.includes("/home/paseo/")) return value.replaceAll(/\/home\/paseo\/[^"\s]*/g, "/tmp/fixture-sandbox");
    return value;
  }
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, item] of Object.entries(value)) {
      // Keep the keys ServerInfo requires, with fixture-safe values.
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

const pending = new Map();
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) =>
  new Promise((resolve) => {
    pending.set(message.requestId, resolve);
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
    save("server_info", msg);
    onReady().catch((error) => {
      console.error("capture failed:", error);
      ws.close(1000);
      process.exit(1);
    });
    return;
  }
};
ws.onclose = (e) => {
  if (e.code !== 1000) console.error("closed", e.code, e.reason);
};
ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-capture-rewind",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.0.1",
      capabilities: { helloRejection: true },
      auth,
    }),
  );

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function onReady() {
  console.log("connected; rewinding one fixture turn on the sandbox agent", AGENT_ID);

  const snapshot = await request({
    type: "fetch_agent_request",
    requestId: "rewind-snapshot",
    agentId: AGENT_ID,
  });
  save("fetch_agent_response", snapshot);
  console.log(
    "snapshot capabilities:",
    JSON.stringify(snapshot.message.payload?.agent?.capabilities),
  );

  // One disposable turn on an idle-capable sandbox: send, wait, rewind it back away.
  const sendResponse = await request({
    type: "send_agent_message_request",
    requestId: "rewind-send",
    agentId: AGENT_ID,
    text: PROMPT,
    messageId: "rewind-fixture-probe-1",
  });
  save("send_agent_message_response", sendResponse);

  const wait = await request({
    type: "wait_for_finish_request",
    requestId: "rewind-wait",
    agentId: AGENT_ID,
    timeoutMs: 120000,
  });
  save("wait_for_finish_response", wait);
  console.log("wait_for_finish status:", wait.message.payload?.status);

  const timeline = await request({
    type: "fetch_agent_timeline_request",
    requestId: "rewind-timeline-before",
    agentId: AGENT_ID,
    direction: "tail",
    limit: 20,
    projection: "projected",
    wholeTurns: true,
  });
  save("fetch_agent_timeline_before", timeline);
  const entries = timeline.message?.payload?.entries ?? [];
  const target = entries.find(
    (entry) =>
      entry.item?.type === "user_message" &&
      (entry.item?.messageId === "rewind-fixture-probe-1" ||
        entry.item?.clientMessageId === "rewind-fixture-probe-1"),
  );
  if (!target) throw new Error("probe message not found in the timeline");
  const messageId = target.item?.messageId ?? target.item?.clientMessageId;
  console.log("rewinding to messageId", messageId);

  const rewindResponse = await request({
    type: "agent.rewind.request",
    requestId: "rewind-request",
    agentId: AGENT_ID,
    messageId,
    mode: "both",
  });
  save("agent_rewind_response", rewindResponse);
  console.log("rewind response:", JSON.stringify(rewindResponse.message?.payload));

  ws.close(1000);
  process.exit(0);
}
