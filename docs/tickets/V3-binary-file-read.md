# V3 — read video/audio bytes through the daemon's binary file channel

Read `ARCHITECTURE.md`, `AGENTS.md`, `docs/tickets/_V-common.md` first.

## Problem (confirmed from upstream source)
`file_explorer_request` mode `file` answers with bytes (base64) only for **images**. For anything
else binary (mp4, wav…) it answers `encoding: "none"` with no content
(`packages/server/src/server/file-explorer/service.ts:208-246`). Our `WorkspaceFiles.fetch` therefore
returns no bytes for `clip.mp4` / `tone.wav` and VideoCard / AudioRow show "Couldn't load".

## The road upstream gives us
`acceptBinary: true` on the request (field already in `PaseoProtocol/Files.swift:116`). When the
session has a binary channel the daemon streams the file as `FileBegin` / `FileChunk`… / `FileEnd`
frames correlated by `requestId` (`workspace-files-session.ts:270-340`, protocol
`binary-frames/file-transfer.ts`; our codec: `PaseoProtocol/FileTransfer.swift`), then answers the
JSON response. Upstream client: `daemon-client.ts` `readFile` (~5590-5670) with
`pendingBinaryFileReads` and the frame handler (~7583). Mirror that: pre-register the requestId,
collect frames, assemble, honour `maxBytes` (daemon already rejects "File is too large to display").

## Do
1. `PaseoKit` / `PaseoStore`: route incoming `.binaryFrame` file-transfer frames by `requestId` to a
   pending read; add `WorkspaceFiles.fetchBytes(path, maxBytes)` (or extend `fetch`) that sends the
   request with `acceptBinary: true` and returns the assembled bytes + mime + revision. Fall back to
   the existing JSON path when the transport has no binary channel (relay without it) and for images.
   Terminal binary frames keep working untouched (different opcodes — check how they are decoded).
2. `ChatController.fetchDaemonMedia` (and `WorkspaceShare.readFile` — Save to Files for video/audio
   currently throws "can't be saved from here") use it, so images, video, audio and Save to Files all
   share one road.
3. Tests (new files, Core, Linux): frame assembly, out-of-order requestIds, missing FileEnd, size
   cap, fallback when no binary channel. Fake client exists for tests.
4. Verify on the simulator (test daemon, port 6768; chat "Rich media test", agent 9972fe65): `clip.mp4`
   plays after tap, `tone.wav` plays. Take no screenshots unless asked; use `ui reading`.

Smoothness: assembling happens off the main actor; no per-chunk UI work; cap respected so a huge
file never holds memory twice. Do not touch claude-provider agents. Commit on your branch, do not push.
