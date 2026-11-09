#!/usr/bin/env node
// Captures real daemon traffic for the schedules area (T9) into
// Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/schedules/.
//
// Only ever touches /tmp/fixture-sandbox: it creates one new-agent schedule there with a
// far-future cron cadence, inspects/updates/pauses/resumes it, runs it once, reads its logs and
// deletes it. The run creates an agent/workspace in the sandbox; the schedule archives the
// workspace on finish, and this script archives the run's agent if it is still around.
//
// Usage: node Tools/capture-schedules.mjs [outDir]
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
// Fixtures may contain the prompt text used below; review before committing.
import fs from "node:fs";
import path from "node:path";

const outDir =
  process.argv[2] ??
  "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/schedules";
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const SANDBOX_CWD = "/tmp/fixture-sandbox";
const PROVIDER = "omp";
const MODEL = "opencode-go/deepseek-v4.1-flash";
const NAME = "T9 fixture schedule";
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
const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));
const request = (message, timeoutMs = 60000) =>
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

let createdId = null;
let runAgentId = null;

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
    // Never leave a schedule (or an agent it spawned) behind, even when a capture step fails.
    onReady().catch(async (error) => {
      console.error(error);
      await cleanup();
      process.exit(1);
    });
  }
};
ws.onclose = (e) => {
  if (e.code !== 1000) console.error("closed", e.code, e.reason);
};
ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-capture-schedules",
      clientType: "mobile",
      protocolVersion: 1,
      // >= 0.1.45: the daemon hides non-legacy providers (pi, omp) from older clients.
      appVersion: "0.1.45",
      capabilities: { helloRejection: true },
      auth,
    }),
  );

async function cleanup() {
  if (createdId) {
    await request({
      type: "schedule/delete",
      requestId: "cleanup-schedule-delete",
      scheduleId: createdId,
    }).catch(() => {});
    console.error(`deleted schedule ${createdId} after failure`);
  }
  if (runAgentId) {
    await request({
      type: "archive_agent_request",
      requestId: "cleanup-archive-agent",
      agentId: runAgentId,
    }).catch(() => {});
    console.error(`archived run agent ${runAgentId} after failure`);
  }
}

async function onReady() {
  // Baseline: only used to prove the RPC works before creating anything.
  await request({ type: "schedule/list", requestId: "list-before" });

  const created = await request({
    type: "schedule/create",
    requestId: "create",
    name: NAME,
    prompt: "Reply with the single word: scheduled",
    cadence: { type: "cron", expression: "0 0 1 1 *", timezone: "UTC" },
    target: {
      type: "new-agent",
      config: {
        provider: PROVIDER,
        cwd: SANDBOX_CWD,
        model: MODEL,
        modeId: "full",
      },
    },
    maxRuns: 2,
  });
  createdId = created.message?.payload?.schedule?.id ?? null;
  if (!createdId) {
    throw new Error(`create failed: ${created.message?.payload?.error ?? "no schedule"}`);
  }
  save("schedule_create_response", created);
  console.log(`created schedule ${createdId}`);

  // The live list may contain schedules from other clients; keep only the one we created.
  const listed = await request({ type: "schedule/list", requestId: "list-after-create" });
  listed.message.payload.schedules = listed.message.payload.schedules.filter(
    (schedule) => schedule.id === createdId,
  );
  save("schedule_list_response", listed);
  console.log(`list: ${listed.message.payload.schedules.length} sandbox schedule`);

  const inspected = await request({
    type: "schedule/inspect",
    requestId: "inspect",
    scheduleId: createdId,
  });
  save("schedule_inspect_response", inspected);

  const updated = await request({
    type: "schedule/update",
    requestId: "update",
    scheduleId: createdId,
    name: "T9 fixture schedule renamed",
    prompt: "Reply with the single word: rescheduled",
    cadence: { type: "cron", expression: "0 0 1 2 *", timezone: "UTC" },
    newAgentConfig: { model: MODEL, modeId: "full" },
    maxRuns: 3,
  });
  save("schedule_update_response", updated);
  console.log(`updated: name=${updated.message.payload.schedule?.name ?? "-"}`);

  const paused = await request({
    type: "schedule/pause",
    requestId: "pause",
    scheduleId: createdId,
  });
  save("schedule_pause_response", paused);
  console.log(`paused: status=${paused.message.payload.schedule?.status ?? "-"}`);

  const resumed = await request({
    type: "schedule/resume",
    requestId: "resume",
    scheduleId: createdId,
  });
  save("schedule_resume_response", resumed);
  console.log(`resumed: status=${resumed.message.payload.schedule?.status ?? "-"}`);

  const emptyLogs = await request({
    type: "schedule/logs",
    requestId: "logs-empty",
    scheduleId: createdId,
  });
  save("schedule_logs_empty_response", emptyLogs);
  console.log(`logs before run: ${emptyLogs.message.payload.runs?.length ?? 0}`);

  const runOnce = await request(
    {
      type: "schedule/run-once",
      requestId: "run-once",
      scheduleId: createdId,
    },
    180000,
  );
  save("schedule_run_once_response", runOnce);
  const runs = runOnce.message.payload.schedule?.runs ?? [];
  const lastRun = runs[runs.length - 1];
  runAgentId = lastRun?.agentId ?? null;
  console.log(
    `run once: status=${lastRun?.status ?? "-"} agent=${runAgentId ?? "-"} error=${lastRun?.error ?? "-"}`,
  );

  const logs = await request({
    type: "schedule/logs",
    requestId: "logs",
    scheduleId: createdId,
  });
  save("schedule_logs_response", logs);

  const deleted = await request({
    type: "schedule/delete",
    requestId: "delete",
    scheduleId: createdId,
  });
  save("schedule_delete_response", deleted);
  console.log(`deleted schedule ${createdId}`);
  createdId = null;

  if (runAgentId) {
    const archived = await request({
      type: "archive_agent_request",
      requestId: "archive-run-agent",
      agentId: runAgentId,
    });
    console.log(`archived run agent ${runAgentId}: ${archived.message?.payload?.archivedAt ? "yes" : "no"}`);
    runAgentId = null;
  }

  ws.close(1000);
  process.exit(0);
}
