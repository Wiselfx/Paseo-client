#!/usr/bin/env node
// Generates the file-transfer binary frame fixtures from the *upstream* codec itself:
// packages/protocol/src/binary-frames/file-transfer.ts in the paseo-reference checkout.
// It does not reimplement anything; it imports the upstream module (with its zod dependency
// stubbed, which only the *decode* path uses) and records the bytes it produces.
//
// Usage: node Tools/capture-file-transfer.mjs [upstreamSrcDir]
// Default upstream dir: /home/paseo/dev/paseo-reference/packages/protocol/src/binary-frames
//
// Output: Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/file-upload/frames.json
// The Swift codec tests read this file and check our encoder/decoder against it both ways.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");
const upstreamSrc = process.argv[2]
  ?? process.env.PASEO_UPSTREAM_SRC
  ?? "/home/paseo/dev/paseo-reference/packages/protocol/src/binary-frames";
const outDir = process.argv[3]
  ?? path.join(repoRoot, "Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/file-upload");

for (const name of ["file-transfer.ts", "terminal.ts"]) {
  if (!fs.existsSync(path.join(upstreamSrc, name))) {
    console.error(`upstream source not found: ${path.join(upstreamSrc, name)}`);
    console.error("Pass the directory or set PASEO_UPSTREAM_SRC.");
    process.exit(1);
  }
}

// Copy the upstream sources into a scratch module dir with zod replaced by a permissive stub.
// The stub only needs to survive module evaluation; encoders never call zod at runtime.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "paseo-file-transfer-"));
fs.writeFileSync(path.join(scratch, "package.json"), JSON.stringify({ type: "module" }));
fs.writeFileSync(path.join(scratch, "zod-stub.mjs"), `
const anySchema = () => {
  const s = {
    safeParse: (v) => ({ success: true, data: v }),
    parse: (v) => v,
  };
  for (const m of ['int','positive','nonnegative','min','max','optional','nullable','default',
                   'describe','regex','email','url','uuid','brand']) {
    s[m] = () => s;
  }
  return s;
};
export const z = new Proxy({}, { get: () => anySchema });
`);
fs.writeFileSync(path.join(scratch, "messages-stub.mjs"), "export const TerminalStateSchema = {};\n");
const rewrite = (name, pairs) => {
  let text = fs.readFileSync(path.join(upstreamSrc, name), "utf8");
  for (const [from, to] of pairs) text = text.split(from).join(to);
  fs.writeFileSync(path.join(scratch, name), text);
};
rewrite("file-transfer.ts", [['import { z } from "zod";', 'import { z } from "./zod-stub.mjs";'], ['"./terminal.js"', '"./terminal.ts"']]);
rewrite("terminal.ts", [['import { z } from "zod";', 'import { z } from "./zod-stub.mjs";'], ['"../messages.js"', '"./messages-stub.mjs"']]);

const codec = await import(pathToFileURL(path.join(scratch, "file-transfer.ts")).href);
const { encodeFileTransferFrame, decodeFileTransferFrame, FileTransferOpcode } = codec;

const req = "req_FIXTURE_upload";
const iso = "2026-11-09T00:00:00.000Z";
const chunk1024 = Buffer.from(Array.from({ length: 1024 }, (_, i) => i & 0xff));

const cases = [
  {
    name: "file-begin",
    input: {
      opcode: FileTransferOpcode.FileBegin,
      requestId: req,
      metadata: {
        mime: "text/plain", size: 11, encoding: "binary",
        modifiedAt: iso, revision: "rev-1", fileName: "hello.txt",
      },
    },
  },
  {
    name: "file-begin-no-optional-fields",
    input: {
      opcode: FileTransferOpcode.FileBegin,
      requestId: req,
      metadata: { mime: "text/plain", size: 11, encoding: "binary", modifiedAt: iso },
    },
  },
  {
    name: "file-begin-utf8-encoding",
    input: {
      opcode: FileTransferOpcode.FileBegin,
      requestId: req,
      metadata: { mime: "text/plain", size: 5, encoding: "utf-8", modifiedAt: iso, fileName: "héllo.txt" },
    },
  },
  {
    name: "file-chunk",
    input: { opcode: FileTransferOpcode.FileChunk, requestId: req, payload: Buffer.from("hello world") },
  },
  {
    name: "file-chunk-1024",
    input: { opcode: FileTransferOpcode.FileChunk, requestId: req, payload: chunk1024 },
  },
  {
    name: "file-chunk-empty",
    input: { opcode: FileTransferOpcode.FileChunk, requestId: req, payload: Buffer.alloc(0) },
  },
  {
    name: "file-end",
    input: { opcode: FileTransferOpcode.FileEnd, requestId: req },
  },
];

const frames = [];
for (const { name, input } of cases) {
  const encoded = encodeFileTransferFrame(input);
  const decoded = decodeFileTransferFrame(encoded);
  if (!decoded) {
    console.error(`upstream decode rejected ${name} right after encoding; refusing to write the fixture`);
    process.exit(1);
  }
  frames.push({
    name,
    opcode: input.opcode,
    requestId: input.requestId,
    ...(input.metadata ? { metadata: input.metadata } : {}),
    ...(input.payload ? { payloadBase64: Buffer.from(input.payload).toString("base64") } : {}),
    encodedBase64: Buffer.from(encoded).toString("base64"),
  });
}

fs.mkdirSync(outDir, { recursive: true });
const manifest = {
  generator: "Tools/capture-file-transfer.mjs",
  source: "upstream packages/protocol/src/binary-frames/file-transfer.ts (zod stubbed)",
  note: "Fixture bytes are the upstream codec's own output; never hand-edit them.",
  frames,
};
fs.writeFileSync(path.join(outDir, "frames.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(`wrote ${path.join(outDir, "frames.json")} (${frames.length} frames)`);
fs.rmSync(scratch, { recursive: true, force: true });
