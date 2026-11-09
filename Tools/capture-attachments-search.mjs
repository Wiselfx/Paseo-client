#!/usr/bin/env node
// Captures real daemon traffic for T12 (attachments, timeline search, provider subagents) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/attachments-search/.
//
// Only touches /tmp/fixture-sandbox: creates one omp agent there, uploads one small text file,
// sends one message carrying structured attachments, runs timeline searches, lists provider
// subagents, then archives the agent. Nothing else is created, killed or archived.
//
// Usage: node Tools/capture-attachments-search.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures contain the prompt and uploaded fixture text below; review before committing.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ??
  "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/attachments-search";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const SANDBOX_CWD = "/tmp/fixture-sandbox";
const PROVIDER = "omp";
const MODEL = "opencode-go/deepseek-v4.1-flash";
const PROMPT = "Reply with the single word: ready";
const UPLOAD_NAME = "t12-fixture-upload.txt";
const UPLOAD_TEXT = "T12 fixture attachment: hello from the sandbox.\n";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : {
      kind: "localCredential",
      token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim(),
    };

fs.mkdirSync(outDir, { recursive: true });

// No hostnames, no daemon server ids, no host-side session/upload paths. The agent id kept is
// the sandbox agent this script created.
function scrub(value) {
  if (typeof value === "string") {
    if (/^srv_/.test(value)) return "srv_FIXTURE";
    if (value.startsWith("/home/paseo/.omp/agent/sessions/")) {
      return "/tmp/fixture-sandbox/.fixture-session.jsonl";
    }
    if (value === UPLOAD_NAME) return UPLOAD_NAME;
    if (value.includes(UPLOAD_NAME) || value.includes("/uploads/")) {
      return `/tmp/fixture-sandbox/${UPLOAD_NAME}`;
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
let ws;
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

function frame(requestId, opcode, payload = new Uint8Array(), metadata) {
  const id = new TextEncoder().encode(requestId);
  if (metadata !== undefined) {
    const json = new TextEncoder().encode(JSON.stringify(metadata));
    const bytes = new Uint8Array(4 + id.byteLength + json.byteLength);
    const view = new DataView(bytes.buffer);
    bytes[0] = opcode;
    bytes[1] = id.byteLength;
    bytes.set(id, 2);
    view.setUint16(2 + id.byteLength, json.byteLength);
    bytes.set(json, 4 + id.byteLength);
    return bytes;
  }
  const bytes = new Uint8Array(2 + id.byteLength + payload.byteLength);
  bytes[0] = opcode;
  bytes[1] = id.byteLength;
  bytes.set(id, 2);
  bytes.set(payload, 2 + id.byteLength);
  return bytes;
}

ws = new WebSocket(url);
ws.binaryType = "arraybuffer";

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
  if (inner.type) events.push(msg);
};
ws.onclose = (e) => {
  if (e.code !== 1000) console.error("closed", e.code, e.reason);
};
ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-capture-attachments-search",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.1.45",
      capabilities: { helloRejection: true, providerSubagents: true },
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

async function upload(bytes) {
  const requestId = "t12-upload";
  const modifiedAt = new Date().toISOString();
  const responsePromise = request({
    type: "file.upload.request",
    requestId,
    fileName: UPLOAD_NAME,
    mimeType: "text/plain",
    size: bytes.byteLength,
    modifiedAt,
  });
  await new Promise((resolve) => setTimeout(resolve, 50));
  ws.send(
    frame(requestId, 0x10, new Uint8Array(), {
      mime: "text/plain",
      size: bytes.byteLength,
      encoding: "binary",
      modifiedAt,
      fileName: UPLOAD_NAME,
    }),
  );
  ws.send(frame(requestId, 0x11, bytes));
  ws.send(frame(requestId, 0x12));
  return responsePromise;
}

async function onReady(serverInfo) {
  save("server_info", serverInfo);

  await request({
    type: "fetch_agents_request",
    requestId: "agents",
    includeBackground: true,
    page: { limit: 50 },
    subscribe: {},
  });

  const created = await request({
    type: "create_agent_request",
    requestId: "create",
    config: { provider: PROVIDER, cwd: SANDBOX_CWD, modeId: "full", model: MODEL },
    initialPrompt: PROMPT,
    labels: { "paseo.fixture": "t12-attachments-search" },
  });
  save("create_agent_response", created);
  createdAgentId = created.message.payload.agentId;
  if (!createdAgentId) throw new Error(`create failed: ${created.message.payload.error}`);
  console.log(`created ${createdAgentId} in ${SANDBOX_CWD}`);

  try {
    // Let the first turn finish so the search fixture covers both roles.
    await waitFor(
      (msg) =>
        msg.message?.type === "agent_stream" &&
        msg.message.payload?.agentId === createdAgentId &&
        msg.message.payload?.event?.type === "turn_completed",
      120000,
      "first turn",
    );

    const uploaded = await upload(new TextEncoder().encode(UPLOAD_TEXT));
    save("file_upload_response", uploaded);
    const file = uploaded.message.payload.file;
    if (!file) throw new Error(`upload failed: ${uploaded.message.payload.error}`);
    console.log(`uploaded ${file.fileName} ${file.size} bytes at ${file.path}`);

    const sent = await request({
      type: "send_agent_message_request",
      requestId: "send-attachments",
      agentId: createdAgentId,
      text: "See the attached fixture note.",
      messageId: "fixture-attachment-message",
      attachments: [
        {
          type: "text",
          mimeType: "text/plain",
          title: "T12 fixture note",
          text: UPLOAD_TEXT,
        },
        file,
      ],
    });
    save("send_agent_message_response", sent);
    if (!sent.message.payload.accepted) {
      throw new Error(`send failed: ${sent.message.payload.error}`);
    }
    console.log("sent message with text + uploaded_file attachments");

    await waitFor(
      (msg) =>
        msg.message?.type === "agent_stream" &&
        msg.message.payload?.agentId === createdAgentId &&
        msg.message.payload?.event?.type === "turn_completed",
      120000,
      "attachment turn",
    );

    const search = await request({
      type: "agent.timeline.search.request",
      requestId: "search",
      agentId: createdAgentId,
      query: "ready",
    });
    save("agent_timeline_search_response", search);
    console.log(
      `search locations: ${search.message.payload.locations.length} nextCursor=${search.message.payload.nextCursor}`,
    );

    const subagents = await request({
      type: "agent.provider_subagents.list.request",
      requestId: "subagents",
      parentAgentId: createdAgentId,
    });
    save("provider_subagents_list_response", subagents);
    console.log(`provider subagents: ${subagents.message.payload.subagents.length}`);

    const archived = await request({
      type: "archive_agent_request",
      requestId: "archive",
      agentId: createdAgentId,
    });
    save("archive_agent_response", archived);
    console.log(`archived ${createdAgentId}`);
    createdAgentId = null;
  } finally {
    if (createdAgentId) {
      await request({
        type: "archive_agent_request",
        requestId: "cleanup-archive",
        agentId: createdAgentId,
      }).catch(() => {});
      console.error(`archived ${createdAgentId} during cleanup`);
    }
    ws.close(1000);
    process.exit(0);
  }
}
