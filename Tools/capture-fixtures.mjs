#!/usr/bin/env node
// Captures real daemon traffic as JSON fixtures for PaseoCore decoding tests.
// Usage: node Tools/capture-fixtures.mjs <outDir> [agentId] [listenSeconds] [prompt]
// With a prompt, it subscribes first and then sends it, so the stream covers a whole turn.
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures may contain your prompts and file paths. Review before committing.
import fs from "node:fs";
import path from "node:path";

const [outDir = "fixtures-out", agentArg, listenArg = "15", promptArg] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

fs.mkdirSync(outDir, { recursive: true });
const save = (name, obj) => fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
const pending = new Map();
let streamCount = 0;
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) => new Promise((resolve) => { pending.set(message.requestId, resolve); send(message); });

ws.onmessage = (e) => {
  if (typeof e.data !== "string") return;
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) { pending.get(reqId)(msg); pending.delete(reqId); return; }
  if (inner.payload?.status === "server_info") { save("server_info", msg); onReady(); return; }
  if (inner.type === "agent_stream" && streamCount < 200) {
    save(`stream_${String(streamCount++).padStart(3, "0")}_${inner.payload.event.type}`, msg);
  } else if (!["agent_stream"].includes(inner.type)) {
    save(`unsolicited_${inner.type}`, msg);
  }
};
ws.onclose = (e) => { if (e.code !== 1000) console.error("closed", e.code, e.reason); };
ws.onopen = () => ws.send(JSON.stringify({
  type: "hello", clientId: "fixture-capture", clientType: "mobile", protocolVersion: 1,
  appVersion: "0.0.1", capabilities: { helloRejection: true }, auth,
}));

async function onReady() {
  const agents = await request({ type: "fetch_agents_request", requestId: "agents", includeBackground: true, page: { limit: 50 } });
  save("fetch_agents_response", agents);
  save("fetch_workspaces_response", await request({ type: "fetch_workspaces_request", requestId: "workspaces", includeBackground: true }));
  const agentId = agentArg ?? agents.message.payload.entries[0]?.agent.id;
  if (agentId) {
    save("fetch_agent_timeline_response", await request({
      type: "fetch_agent_timeline_request", requestId: "timeline", agentId,
      direction: "tail", limit: 40, projection: "projected", wholeTurns: true,
    }));
  }
  if (agentId) {
    save("set_subscription_response", await request({
      type: "agent.timeline.set_subscription.request", requestId: "sub", agentIds: [agentId],
    }));
  }
  if (agentId && promptArg) {
    save("send_agent_message_response", await request({
      type: "send_agent_message_request", requestId: "send", agentId, text: promptArg, messageId: "fixture-msg-1",
    }));
  }
  console.log(`listening ${listenArg}s for stream events…`);
  setTimeout(() => { console.log(`stream events: ${streamCount}`); ws.close(1000); process.exit(0); }, Number(listenArg) * 1000);
}
