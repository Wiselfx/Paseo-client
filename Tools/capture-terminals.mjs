#!/usr/bin/env node
// Captures real terminal and workspace-script traffic for PaseoCore fixtures.
//
//   node Tools/capture-terminals.mjs <outDir> <workspaceId> <cwd> terminal
//   node Tools/capture-terminals.mjs <outDir> <workspaceId> <cwd> scripts [scriptName]
//
// Only operate on /tmp/fixture-sandbox or /tmp/fixture-terminals. The terminal mode creates one
// terminal and kills it. The scripts mode lists, starts, then stops one configured script (the
// daemon owns its backing terminal). Auth: PASEO_PASSWORD or $PASEO_HOME/local-credential.
import fs from "node:fs";
import path from "node:path";

const [outDir = "fixtures-out", workspaceId, cwd, mode = "terminal", scriptName = "fixture"] =
  process.argv.slice(2);
if (!workspaceId || !cwd) {
  console.error("usage: capture-terminals.mjs <outDir> <workspaceId> <cwd> <terminal|scripts> [scriptName]");
  process.exit(2);
}
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

fs.mkdirSync(outDir, { recursive: true });
const frameDir = path.join(outDir, "frames");
fs.mkdirSync(frameDir, { recursive: true });

const save = (name, obj) => {
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
};
const pending = new Map();
const pushCounts = new Map();
let frameCount = 0;
let requestSeq = 0;
const ws = new WebSocket(url);
ws.binaryType = "arraybuffer";

const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) => new Promise((resolve) => {
  const requestId = message.requestId ?? `capture-${++requestSeq}`;
  pending.set(requestId, resolve);
  send({ ...message, requestId });
});
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

ws.onopen = () => ws.send(JSON.stringify({
  type: "hello", clientId: "fixture-terminal-capture", clientType: "mobile", protocolVersion: 1,
  appVersion: "0.0.1",
  // Same capabilities the iOS client advertises: chunked replay, no owned subscriptions.
  capabilities: { hello_rejection: true, terminal_chunked_replay: true },
  auth,
}));

ws.onmessage = (event) => {
  if (typeof event.data !== "string") {
    const bytes = Buffer.from(event.data);
    if (bytes.length < 2) return;
    const opcode = bytes[0];
    const slot = bytes[1];
    const payload = bytes.subarray(2);
    const record = {
      opcode,
      slot,
      payloadBase64: payload.toString("base64"),
      payloadLength: payload.length,
    };
    const text = payload.toString("utf8");
    if (opcode === 0x06 || (opcode >= 0x20 && text.startsWith("{"))) record.payloadText = text;
    save(path.join("frames", `frame_${String(frameCount++).padStart(3, "0")}_opcode${opcode}`), record);
    return;
  }

  const msg = JSON.parse(event.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) {
    pending.get(reqId)(msg);
    pending.delete(reqId);
    return;
  }
  if (inner.payload?.status === "server_info") {
    onReady();
    return;
  }

  const type = inner.type;
  // Never persist unrelated broadcasts (agent streams include other agents' prompts and output).
  const captured = new Set([
    "terminals_changed",
    "terminal_stream_exit",
    "terminal_attention_required",
    "script_status_update",
  ]);
  if (type === "status" && inner.payload?.status === "error") {
    console.error("daemon rejected a message:", inner.payload.message);
    process.exitCode = 1;
    return;
  }
  if (type && captured.has(type)) {
    const count = pushCounts.get(type) ?? 0;
    pushCounts.set(type, count + 1);
    save(`${type}_${String(count).padStart(3, "0")}`, msg);
  }
};

ws.onclose = (event) => {
  if (event.code !== 1000) console.error("closed", event.code, event.reason);
};

ws.onerror = (event) => console.error("websocket error", event.message ?? event);

async function onReady() {
  // The shipped daemon still requires `cwd` on directory subscriptions even though the schema in
  // upstream main marks it optional; send both keys.
  send({ type: "subscribe_terminals_request", workspaceId, cwd });
  await sleep(400);
  save("list_terminals_response", await request({ type: "list_terminals_request", workspaceId }));

  if (mode === "scripts") {
    await runScripts();
  } else {
    await runTerminal();
  }
  await sleep(800);
  ws.close(1000);
  process.exit(0);
}

async function runTerminal() {
  const created = await request({
    type: "create_terminal_request", workspaceId, cwd, name: "fixture-terminal",
  });
  save("create_terminal_response", created);
  const terminalId = created.message?.payload?.terminal?.id;
  if (!terminalId) {
    console.error("create did not return a terminal");
    process.exit(1);
  }

  save("subscribe_terminal_response", await request({
    type: "subscribe_terminal_request", terminalId,
    restore: { mode: "visible-snapshot", scrollbackLines: 200, size: { rows: 24, cols: 80 } },
  }));
  await sleep(500);

  send({
    type: "terminal_input", terminalId, message: { type: "input", data: "printf 'hello\\n'; ls\r" },
  });
  await sleep(2000);

  save("kill_terminal_response", await request({ type: "kill_terminal_request", terminalId }));
  await sleep(800);
}

async function runScripts() {
  save("workspace_script_list_response", await request({
    type: "workspace.script.list.request", workspaceId,
  }));
  save("workspace_script_start_response", await request({
    type: "workspace.script.start.request", workspaceId, scriptName,
  }));
  await sleep(1500);
  save("workspace_script_stop_response", await request({
    type: "workspace.script.stop.request", workspaceId, scriptName,
  }));
  await sleep(1200);
}
