// Captures the agent-lifecycle traffic (archive / unarchive / delete / history listing) from the
// fixture daemon. Creates TWO throwaway agents in /tmp/fixture-sandbox, archives both, pages a
// SEARCH-FILTERED history ("M7e fixture") so the fixture only ever contains the agents this
// script created, refreshes one back to life, then deletes both. Usage:
//   node Tools/capture-agent-lifecycle.mjs <outDir>
import fs from "node:fs";
import path from "node:path";
const [outDir = "fixtures-out"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };
const sandbox = "/tmp/fixture-sandbox";
const provider = process.env.PASEO_PROVIDER ?? "omp";
const model = process.env.PASEO_MODEL ?? "opencode-go/deepseek-v4.1-flash";
const search = "M7e fixture";

fs.mkdirSync(outDir, { recursive: true });
const save = (name, envelope) => fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(envelope, null, 2) + "\n");
const payloadOf = (envelope) => envelope?.message?.payload ?? envelope?.payload ?? envelope;
const log = (...a) => console.log(new Date().toISOString(), ...a);
const ws = new WebSocket(url);
const pending = new Map();
let counter = 0;
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) => {
  const withId = { requestId: `m7e-${++counter}`, ...message };
  send(withId);
  return new Promise((resolve) => pending.set(withId.requestId, resolve));
};
ws.onmessage = (e) => {
  if (typeof e.data !== "string") return;
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) { pending.get(reqId)(msg); pending.delete(reqId); return; }
  if (inner.payload?.status === "server_info") onReady();
};
ws.onerror = (e) => { log("error", e?.message ?? e); process.exit(1); };
ws.onclose = (e) => { log("closed", e?.code, e?.reason); process.exit(1); };
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: "hello", clientId: "m7e-capture", clientType: "mobile",
    protocolVersion: 1, appVersion: "0.1.45", capabilities: { helloRejection: true }, auth,
  }));
};
async function onReady() {
  log("ready");
  const created = [];
  for (const title of ["M7e fixture A", "M7e fixture B"]) {
    log("creating", title);
    const envelope = await request({
      type: "create_agent_request",
      config: { provider, cwd: sandbox, model, title },
      initialPrompt: "Reply with the single word: ready",
    });
    const payload = payloadOf(envelope);
    const agent = payload?.status === "agent_created" ? payload.agent : null;
    if (!agent) throw new Error(`create failed for "${title}": ${JSON.stringify(envelope)}`);
    created.push(agent);
    log("created", agent.id, agent.title);
  }
  const [agentA, agentB] = created;

  log("waiting for turns to settle…");
  const settleDeadline = Date.now() + 180_000;
  for (const agent of created) {
    while (Date.now() < settleDeadline) {
      const snapshot = await request({ type: "fetch_agent_request", agentId: agent.id });
      const turn = payloadOf(snapshot)?.agent?.activeTurn;
      if (!turn) break;
      await new Promise((r) => setTimeout(r, 1000));
    }
    log("turn settled for", agent.title);
  }

  for (const agent of [agentA, agentB]) {
    const envelope = await request({ type: "archive_agent_request", agentId: agent.id });
    log("archive", agent.id, JSON.stringify(payloadOf(envelope)));
    save(`archive_agent_response_${agent === agentA ? "a" : "b"}`, envelope);
  }

  const page1 = await request({
    type: "fetch_agent_history_request",
    search,
    sort: [{ key: "updated_at", direction: "desc" }],
    page: { limit: 1 },
  });
  save("history_page1", page1);
  log("page1 entries:", payloadOf(page1)?.entries?.length,
    "nextCursor:", payloadOf(page1)?.pageInfo?.nextCursor ?? null,
    "hasMore:", payloadOf(page1)?.pageInfo?.hasMore);
  const cursor = payloadOf(page1)?.pageInfo?.nextCursor ?? null;
  if (cursor) {
    const page2 = await request({
      type: "fetch_agent_history_request",
      search,
      sort: [{ key: "updated_at", direction: "desc" }],
      page: { limit: 1, cursor },
    });
    save("history_page2", page2);
    log("page2 entries:", payloadOf(page2)?.entries?.length);
  }

  const refresh = await request({ type: "refresh_agent_request", agentId: agentA.id });
  save("refresh_agent_response", refresh);
  log("refresh a:", payloadOf(refresh)?.status, "requestId:", payloadOf(refresh)?.requestId);

  const fetched = await request({ type: "fetch_agent_request", agentId: agentA.id });
  save("fetch_agent_response", fetched);
  log("fetch a: archivedAt =", payloadOf(fetched)?.agent?.archivedAt ?? null);

  await request({ type: "archive_agent_request", agentId: agentA.id });
  for (const agent of [agentA, agentB]) {
    const envelope = await request({ type: "delete_agent_request", agentId: agent.id });
    log("delete", agent.id, JSON.stringify(payloadOf(envelope)));
    save(`delete_agent_response_${agent === agentA ? "a" : "b"}`, envelope);
  }

  const after = await request({ type: "fetch_agent_history_request", search, page: { limit: 10 } });
  save("history_after_delete", after);
  log("history entries after delete:", payloadOf(after)?.entries?.length);

  process.exit(0);
}
setTimeout(() => { log("timeout"); process.exit(1); }, 180000);
