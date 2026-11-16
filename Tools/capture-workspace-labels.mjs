// Captures workspace-label traffic from the fixture daemon. Operates ONLY on the /tmp/fixture-sandbox
// workspace wks_REPLACE_ME (a throwaway "main" checkout): creates one label, renames/recolors it,
// inspects and deletes it, and saves the wire frames. Nothing else is touched.
//
// Usage: node Tools/capture-workspace-labels.mjs <outDir> [workspaceId]
import fs from "node:fs";
import path from "node:path";
const [outDir = "fixtures-out", workspaceId = "wks_f2b1d5f2155a49aa"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };
const LABEL = "M2.12 capture label";
const RENAMED = "M2.12 capture renamed";

fs.mkdirSync(outDir, { recursive: true });
const save = (name, obj) => fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
const log = (...a) => console.log(new Date().toISOString(), ...a);
const ws = new WebSocket(url);
const pending = new Map();
let counter = 0;
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message) => {
  const withId = { requestId: `m212-${++counter}`, ...message };
  send(withId);
  return new Promise((resolve) => pending.set(withId.requestId, resolve));
};
const events = [];
ws.onmessage = (e) => {
  if (typeof e.data !== "string") return;
  const msg = JSON.parse(e.data);
  const inner = msg.message ?? msg;
  const reqId = inner.payload?.requestId;
  if (reqId && pending.has(reqId)) { pending.get(reqId)(msg); pending.delete(reqId); return; }
  if (inner.type === "workspace.label.update") { events.push(msg); return; }
  if (inner.payload?.status === "server_info") onReady();
};
ws.onerror = (e) => { console.error("error", e?.message ?? e); process.exit(1); };
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: "hello", clientId: "m212-capture", clientType: "mobile",
    protocolVersion: 1, appVersion: "0.1.45", capabilities: { helloRejection: true }, auth,
  }));
};
async function onReady() {
  log("ready");

  const before = await request({ type: "workspace.label.list.request", requestId: "list1" });
  save("label_list_before", before);
  console.log("list before:", payloadOf(before)?.labels?.length, "labels");

  // Subscribe so the catalog pushes land on this socket; the subscriptionId is not committed.
  const subbed = await request({ type: "workspace.label.list.request", requestId: "list2", subscribe: {} });
  save("label_list_subscribed", subbed);

  const assign = await request({
    type: "workspace.label.assignment.set.request",
    requestId: "assign1",
    workspaceId,
    label: { name: LABEL, color: "teal" },
    assigned: true,
  });
  save("label_assign_response", assign);
  console.log("assigned:", payloadOf(assign)?.label);

  const after = await request({ type: "workspace.label.list.request", requestId: "list3" });
  save("label_list_after_assign", after);

  const update = await request({
    type: "workspace.label.update.request",
    requestId: "update1",
    name: LABEL,
    newName: RENAMED,
    color: "sky",
  });
  save("label_update_response", update);
  console.log("updated:", payloadOf(update)?.label, "affected:", payloadOf(update)?.affectedWorkspaceCount);

  const inspect = await request({ type: "workspace.label.delete.inspect.request", requestId: "inspect1", name: RENAMED });
  save("label_delete_inspect_response", inspect);
  console.log("inspect affected:", payloadOf(inspect)?.affectedWorkspaceCount);

  const deletedResponse = await request({ type: "workspace.label.delete.request", requestId: "delete1", name: RENAMED });
  save("label_delete_response", deletedResponse);
  console.log("delete affected:", payloadOf(deletedResponse)?.affectedWorkspaceCount);

  const afterDelete = await request({ type: "workspace.label.list.request", requestId: "list4" });
  save("label_list_after_delete", afterDelete);

  // Give the pushes a moment to arrive, then save them.
  await new Promise((r) => setTimeout(r, 500));
  save("label_update_events", { type: "events", events });
  console.log("saved", events.length, "label update events");
  process.exit(0);
}
function payloadOf(envelope) { return envelope?.message?.payload ?? envelope?.payload ?? envelope; }
setTimeout(() => { console.error("timeout"); process.exit(1); }, 30000);
