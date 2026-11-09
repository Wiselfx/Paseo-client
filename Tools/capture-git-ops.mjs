#!/usr/bin/env node
// Captures real daemon traffic for T15 (git actions, commit log, file entry operations).
//
// Only touches /tmp/fixture-sandbox, a registered git workspace. Creates a scratch
// `.t15-fixture` directory, exercises the entry RPCs and the commits RPCs, then deletes
// everything it created. No push, no PRs, no other workspaces.
//
// Usage: node Tools/capture-git-ops.mjs <outDir>
// Auth: PASEO_PASSWORD, or the local credential at $PASEO_HOME/local-credential.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const [outDir = "fixtures-git-ops"] = process.argv.slice(2);
const url = process.env.PASEO_URL ?? "ws://127.0.0.1:6767/ws";
const home = process.env.PASEO_HOME ?? "/home/paseo/.paseo";
const auth = process.env.PASEO_PASSWORD
  ? { kind: "password", password: process.env.PASEO_PASSWORD }
  : { kind: "localCredential", token: fs.readFileSync(path.join(home, "local-credential"), "utf8").trim() };

const ROOT = "/tmp/fixture-sandbox";
const FIXTURE_DIR = path.join(ROOT, ".t15-fixture");
const SCRATCH = path.join(FIXTURE_DIR, "scratch.txt");
const RENAMED = path.join(FIXTURE_DIR, "renamed.txt");

fs.mkdirSync(outDir, { recursive: true });
const pending = new Map();
let nextRequest = 0;

const ws = new WebSocket(url);
const send = (message) => ws.send(JSON.stringify({ type: "session", message }));

function request(type, fields = {}) {
  const requestId = `t15-${nextRequest++}`;
  const message = { type, requestId, ...fields };
  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject });
    send(message);
  });
}

const save = (name, obj) => {
  fs.writeFileSync(path.join(outDir, name + ".json"), JSON.stringify(obj, null, 2) + "\n");
  console.log(`saved ${name}`);
};

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Hand-clean the sandbox whatever happens: never leave our fixture dir behind.
function removeFixtureDir() {
  fs.rmSync(FIXTURE_DIR, { recursive: true, force: true });
}

process.on("exit", removeFixtureDir);
process.on("SIGINT", () => {
  removeFixtureDir();
  process.exit(130);
});

ws.onmessage = (event) => {
  if (typeof event.data !== "string") return;
  const message = JSON.parse(event.data);
  const inner = message.message ?? message;
  const requestId = inner.payload?.requestId;
  if (requestId && pending.has(requestId)) {
    const { resolve, reject } = pending.get(requestId);
    pending.delete(requestId);
    if (inner.type === "rpc_error") reject(new Error(`${inner.payload.requestType}: ${inner.payload.error}`));
    else resolve(message);
    return;
  }
  if (inner.payload?.status === "server_info") {
    onReady().catch((error) => {
      console.error("capture failed:", error);
      removeFixtureDir();
      ws.close(1000);
      process.exit(1);
    });
  }
};

ws.onclose = (event) => {
  if (event.code !== 1000) console.error("closed", event.code, event.reason);
};

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: "hello",
      clientId: "fixture-git-ops",
      clientType: "mobile",
      protocolVersion: 1,
      appVersion: "0.1.45",
      capabilities: { helloRejection: true },
      auth,
    }),
  );

async function onReady() {
  removeFixtureDir();
  fs.mkdirSync(FIXTURE_DIR);

  save("commits_list_response", await request("checkout.commits.list.request", { cwd: ROOT }));

  const listMessage = JSON.parse(fs.readFileSync(path.join(outDir, "commits_list_response.json"), "utf8"));
  const first = listMessage.message.payload.commits?.[0];
  if (first) {
    save(
      "commits_file_diff_response",
      await request("checkout.commits.file_diff.request", {
        cwd: ROOT,
        sha: first.sha,
        path: "README.md",
      }),
    );
  } else {
    console.log("no commits ahead of base; skipping commits_file_diff_response");
  }

  save(
    "fs_entry_create_response",
    await request("fs.entry.create.request", {
      cwd: ROOT,
      parentPath: ".t15-fixture",
      name: "scratch.txt",
      kind: "file",
    }),
  );
  fs.writeFileSync(SCRATCH, "before write\n");

  const read = await request("file_explorer_request", {
    cwd: ROOT,
    path: ".t15-fixture/scratch.txt",
    mode: "file",
  });
  const modifiedAt = read.message.payload.file?.modifiedAt;

  save(
    "fs_file_write_response",
    await request("fs.file.write.request", {
      cwd: ROOT,
      path: ".t15-fixture/scratch.txt",
      content: "after write\n",
      expectedModifiedAt: modifiedAt,
    }),
  );

  save(
    "fs_entry_rename_response",
    await request("fs.entry.rename.request", {
      cwd: ROOT,
      path: ".t15-fixture/scratch.txt",
      name: "renamed.txt",
    }),
  );

  const duplicated = await request("fs.entry.duplicate.request", {
    cwd: ROOT,
    path: ".t15-fixture/renamed.txt",
  });
  save("fs_entry_duplicate_response", duplicated);
  const duplicatedPath = duplicated.message.payload.duplicatedPath;

  save(
    "fs_entry_delete_response",
    await request("fs.entry.delete.request", {
      cwd: ROOT,
      path: ".t15-fixture/renamed.txt",
    }),
  );
  if (duplicatedPath) {
    save(
      "fs_entry_delete_copy_response",
      await request("fs.entry.delete.request", {
        cwd: ROOT,
        path: duplicatedPath,
      }),
    );
  } else {
    console.log("duplicate returned no path; skipping copy delete");
  }

  await delay(300);
  removeFixtureDir();
  console.log("fixtures cleaned up: .t15-fixture removed");
  ws.close(1000);
  process.exit(0);
}
