# Protocol research — terminals and workspace scripts

Source: `/home/paseo/dev/paseo-reference` (Paseo daemon + Expo app, read at `main`). All paths below are relative to that repo root unless noted; paths starting `app/` are relative to `packages/app/src`. Every claim cites `path:line`. Line numbers were re-opened and checked against the checkout; see the final line of this file.

Target context: a native iOS client rendering terminals with SwiftTerm, which consumes raw ANSI bytes. Wire bytes first, schemas second.

## 0. Transports in one paragraph

The daemon speaks WebSocket with JSON text frames and binary frames on the same connection (`docs/architecture.md:247`). JSON session messages are wrapped in a top-level WS envelope: `hello`, `recording_state`, `ping`/`pong`, `session` (the rich session union lives in `packages/protocol/src/messages.ts`) (`docs/architecture.md:277`). Terminal I/O rides binary frames with a 2-byte header (`packages/protocol/src/binary-frames/terminal.ts:16-25`, `:77-103`). Terminal subscribes/inputs/captures are JSON session messages (`docs/architecture.md:300`). Client liveness is app-level `ping`/`pong` JSON, not RFC6455 control frames; two misses tear down the socket (`docs/architecture.md:279`). Every physical send path enforces an 8 MiB outbound high-water mark; a frame that would cross it forcibly terminates that physical socket (`docs/architecture.md:281`). Session RPCs default to a 60 s wait, correlated by `requestId`; failures come back as `rpc_error` (`docs/architecture.md:283`, `:302`).

## 1. Hello and the capabilities a client must advertise

### The `hello` handshake

- **Client → Server**: WS-level message `hello` — `clientId`, `clientType: "mobile" | "browser" | "cli" | "mcp" | "hub"`, `protocolVersion` (int), optional `appVersion`, optional `auth` (`password` or `localCredential`), optional `capabilities` object with `.passthrough()` — `packages/protocol/src/messages.ts:7973-8012`. A native iOS client should use `clientType: "mobile"`.
- **Server → Client**: no dedicated welcome. After accepting hello the daemon emits one initial WS `session` envelope whose message is a `status` message with payload `{ status: "server_info", serverId, hostname?, version?, protocolVersion?, capabilities?, features }` — `packages/protocol/src/messages.ts:8025-8028` wraps it; the payload schema is `ServerInfoStatusPayloadSchema` at `packages/protocol/src/messages.ts:3796` with the literal `status: "server_info"` at `:3798`, optional `protocolVersion` at `:3799`, and `features` at `:3811`.
- If hello is rejected with `hello.auth` or the client advertised `hello_rejection`, the daemon sends WS `hello.rejected` (`reason: password_required | incorrect_password | incompatible_protocol`) before an auth close; older clients just get the WS close code — `packages/protocol/src/messages.ts:8030-8034`, `docs/protocol-compatibility.md:13`.
- The daemon accepts a client protocol version from its minimum through newer client versions and selects the lower of client and daemon maximum, reported as optional `server_info.protocolVersion` — `docs/protocol-compatibility.md:13`.
- Each physical socket owns its capabilities and subscriptions; the send boundary requires that source's request/subscription provenance — `docs/architecture.md:270-274`.

### Capability advertisement model

Client capabilities ride in `hello.capabilities`. The installed client (SDK) advertises an exhaustive default set; the app inherits it and only supplies host resources or explicit overrides — `packages/client/src/connection/index.ts:35-42`, `:127-151`, `docs/protocol-compatibility.md:43-49`. A schema accepting a message does not imply the delivery semantics behind it — `docs/protocol-compatibility.md:47-49`.

### Hello capabilities required for the modern terminal format

Modern terminal format = **chunked ANSI replay** delivered as binary opcodes `ReplayBegin`/`ReplayData`/`ReplayEnd` (§5.4). To receive it, the client must advertise **`terminal_chunked_replay`** in hello. The daemon reads it per physical source at snapshot send time — `packages/server/src/server/session.ts:1188-1189`; the delivery layer branches on it at `packages/server/src/terminal/terminal-session-controller.ts:1111-1120` via `createTerminalRestoreDelivery({ ..., chunked })`. Without it, the daemon coalesces the replay and sends a single `Restore` (0x05) frame instead — `packages/server/src/terminal/terminal-restore.ts:71-83`.

Full modern-terminal checklist for hello:

| Capability (hello) | Constant | Constant location | What it unlocks |
|---|---|---|---|
| `terminal_chunked_replay` | `CLIENT_CAPS.terminalChunkedReplay` | `packages/protocol/src/client-capabilities.ts:2` | `ReplayBegin`/`ReplayData`/`ReplayEnd` opcodes; without it the client gets one `Restore` frame — `docs/protocol-compatibility.md:61-66` |
| `binary_chunking_v1` | `CLIENT_CAPS.binaryChunkingV1` | `packages/protocol/src/client-capabilities.ts:3` | Connection-scoped ordered framing, opcode `0x31`, for messages bigger than the transport frame budget — `packages/protocol/src/chunked-transport.ts:8-9`, `:106-128`; negotiated per connection at `packages/server/src/server/websocket-server.ts:1301`; server feature `server_info.features.binaryChunkingV1` at `packages/server/src/server/websocket-server.ts:2031`, schema at `packages/protocol/src/messages.ts:4002` and `:4000-4002` |
| `hello_rejection` | `CLIENT_CAPS.helloRejection` | `packages/protocol/src/client-capabilities.ts:4` | `hello.rejected` frames instead of a bare WS close on auth failure — `packages/protocol/src/messages.ts:8030-8034`, `docs/protocol-compatibility.md:13` |
| `owned_subscriptions` | `CLIENT_CAPS.ownedSubscriptions` | `packages/protocol/src/client-capabilities.ts:6` | Source-owned subscriptions: `session.events.set_subscription.request`, server-assigned subscription IDs, `subscription.release.request`; the SDK defaults to them — `packages/client/src/connection/index.ts:130-131`, `packages/protocol/src/messages.ts:3402-3410`; legacy socket path is `unsubscribe_terminal_request` which throws for modern sources — `packages/server/src/server/session/owned-subscriptions/index.ts:391-398` |
| `terminal_reflowable_snapshot` | `CLIENT_CAPS.terminalReflowableSnapshot` | `packages/protocol/src/client-capabilities.ts:26` | Daemon attaches `gridWrapped`/`scrollbackWrapped` soft-wrap flags to `TerminalState` snapshots; old strict clients reject them — `packages/protocol/src/messages.ts:6801-6805`, `docs/protocol-compatibility.md` (COMPAT note inline) |
| `explicit_event_subscriptions` | `CLIENT_CAPS.explicitEventSubscriptions` | `packages/protocol/src/client-capabilities.ts:9` | Event-stream subscriptions (`session.events.set_subscription.request`) instead of broadcast-only delivery; required for `terminal_attention_required` and `script_status_update` demand semantics — `packages/protocol/src/messages.ts:3359-3377` |

The SDK's exhaustive default set lives at `packages/client/src/connection/index.ts:127-151` (includes `terminalChunkedReplay: true` at `:128`, `binaryChunkingV1: true` at `:129`, `helloRejection: true` at `:130`, `ownedSubscriptions: true` at `:131`, `terminalReflowableSnapshot: true` at `:136`). The `hello.capabilities` schema is `.passthrough()` and does not declare `terminal_chunked_replay` / `binary_chunking_v1` explicitly — `packages/protocol/src/messages.ts:7990-8011` — so unknown keys are accepted either way.

**Daemon features the client must check on `server_info` (not hello):**

| Feature (`server_info.features`) | Schema line | Gate for |
|---|---|---|
| `terminal-restore-modes` | `packages/protocol/src/messages.ts:3903` | Modern terminals at all. Terminals require it; older hosts show an update message without attaching — `docs/protocol-compatibility.md:67`. The app throws in `resolveTerminalRestoreOptions` when absent — `app/terminal/runtime/terminal-restore-options.ts:14-16` |
| `terminal-input-mode-replay` | `packages/protocol/src/messages.ts:3905` | Input-mode (Kitty / Win32) replay preambles are carried faithfully; read by the app at `app/components/terminal-pane.tsx:304-306` |
| `terminal-size-ownership` | `packages/protocol/src/messages.ts:3907` | Resize `intent: "claim" | "update"` semantics — older daemons treat every resize as a claim — `packages/server/src/terminal/terminal-size-ownership.ts:31-38` |
| `terminal-grapheme-widths` | `packages/protocol/src/messages.ts:3909` | Daemon buffer uses grapheme widths; a client whose width table disagrees moves the cursor — `docs/terminal-rendering.md:23`, `app/components/terminal-pane.tsx:310-313` |
| `binaryChunkingV1` | `packages/protocol/src/messages.ts:4002` | Both ends negotiated chunked framing |
| `workspaceTerminals` | `packages/protocol/src/messages.ts:3845` | SDK workspace-scoped terminal list/create actions; the SDK throws otherwise — `packages/client/src/terminals/index.ts:87-91` |
| `terminalCollection` | `packages/protocol/src/messages.ts:3839` | Directory subscription (`subscribe_terminals_request`) without a `cwd` filter — the SDK gates on it when `cwd` is omitted — `packages/client/src/daemon-client.ts:6724-6732` |
| `workspaceScriptManagement` | `packages/protocol/src/messages.ts:4014` | Script RPCs; the CLI gates on it — `packages/cli/src/commands/script/shared.ts:17-20` |
| `terminalsSurviveRestart` | `packages/protocol/src/messages.ts:3945` | Daemon stop/restart keeps terminals; old daemons ignore `keepTerminals` — `docs/terminal-worker.md` (Desktop), `packages/client/src/daemon-client.ts:1340-1368` |

## 2. Listing terminals and the directory stream

### 2.1 `list_terminals_request` — one-shot list

- **Name and purpose**: fetch the terminals of a host (optionally scoped), correlated by `requestId`.
- **Request**: `type: "list_terminals_request"` — `packages/protocol/src/messages.ts:3149-3154`. Fields: `cwd?: string`, `workspaceId?: string`, `requestId: string`.
- **Response**: `list_terminals_response` — `packages/protocol/src/messages.ts:6806-6813`. Payload: `cwd?: string`, `terminals: TerminalInfo[]` (with `cwd` made optional for older per-cwd listings, via `.partial({ cwd: true })`), `requestId: string`.
- **`TerminalInfo`**: `createdAt?: string|null`, `isScript?: boolean`, `id: string`, `name: string`, `cwd: string`, `workspaceId?: string`, `title?: string`, `activity?: TerminalActivity|null` — `packages/protocol/src/messages.ts:6755-6764`.
- **Capability gates**: none for the RPC itself. The SDK wraps this in workspace-scoped actions and gates those on `features.workspaceTerminals` — `packages/protocol/src/messages.ts:3845`, `packages/client/src/terminals/index.ts:85-93`. `isScript` is computed daemon-side by matching terminal ids against script runtime entries — `packages/server/src/server/session.ts:1193-1197`.
- **How the app/SDK uses it**: `daemon-client.listTerminals(cwd?, requestId?, { workspaceId })` — `packages/client/src/daemon-client.ts:6738-6756` — parses and returns the payload. SDK facade `terminals.list(...)` parses each entry (id/workspaceId/cwd/name) — `packages/client/src/terminals/index.ts:4-10`, `:94-102`.
- **Gotchas**:
  - `TerminalInfo` is `.partial({ cwd: true })` on the wire for backwards compatibility, but terminals created through the current daemon always carry `cwd`.
  - Terminals are `workspaceId`-scoped in visibility: a same-`cwd` sibling workspace does not see them — `docs/terminal-activity.md:35`.
  - The daemon can terminate terminals at stop/restart unless `keepTerminals` is set; records from an earlier boot are retired without signaling — `docs/terminal-worker.md` (Desktop, Known limits).

### 2.2 `subscribe_terminals_request` / `terminals_changed` — live directory stream

- **Name and purpose**: subscribe to the set of terminals (optionally scoped to a workspace root directory or a workspaceId); the daemon pushes a fresh full `terminals_changed` snapshot on every relevant change (create/kill/title/activity/isScript).
- **Request**: `type: "subscribe_terminals_request"` — `packages/protocol/src/messages.ts:3156-3161`. Fields: `requestId?: string`, `cwd?: string`, `workspaceId?: string`.
- **Response / frames**: there is no correlated response. The initial snapshot and every later change arrive as `terminals_changed` pushes — `packages/protocol/src/messages.ts:6815-6824`. Payload: `subscriptionId?: string`, `requestId?: string`, `workspaceId?: string`, `cwd?: string`, `terminals: TerminalInfo[]`.
- **Capability gates**: omitting `cwd` means "all terminals on the host", gated by `features.terminalCollection` (COMPAT since v0.16) — schema `packages/protocol/src/messages.ts:3839`, server advertises it at `packages/server/src/server/websocket-server.ts:2044`, and the SDK refuses without it — `packages/client/src/daemon-client.ts:6724-6732`. Directory subscriptions with a `cwd` are always allowed. Directory subscription keys are `(cwd, workspaceId)` pairs, not cwd alone — `packages/protocol/src/terminal-subscription-key.ts:1-13`.
- **How the app/SDK uses it**: `daemon-client.observeTerminals({ cwd?, workspaceId?, signal? })` returns an `OwnedSubscription<terminals_changed>`; the SDK routes updates by `subscriptionId` — `packages/client/src/daemon-client.ts:6719-6736`. The server delivers snapshots with volatile `requestId` only on the first pass (`packages/server/src/terminal/terminal-session-controller.ts:404-421`), handles `requestId` correlation on subscribe (`:372-373`), aggregates per subscribed root (`:329-343`), and terminates replay-capable listings with `TerminalWorkerIncompatibleError` when a newer worker holds the home — `:376-380`.
- **Unsubscribe**: `unsubscribe_terminals_request` — `type: "unsubscribe_terminals_request"`, fields `cwd?: string`, `workspaceId?`, no `requestId`, no response — `packages/protocol/src/messages.ts:3163-3167`. Server releases the legacy slot `terminal-directory:<key>` — `packages/server/src/terminal/terminal-session-controller.ts:215-219`. Modern clients (owned subscriptions) release through `subscription.release.request` instead; the daemon throws on `releaseLegacySlot` for modern sources — `packages/server/src/server/session/owned-subscriptions/index.ts:391-398`. The SDK's `OwnedSubscription.release()` sends `subscription.release.request` — `packages/client/src/daemon-client.ts:1401-1413`, schema `packages/protocol/src/messages.ts:3402-3410`.
- **Gotchas**:
  - The subscription is source-owned: it survives nothing — connection teardown drops it and reconnect creates new subscription IDs — `docs/architecture.md:270-275`.
  - A snapshot always carries the *full* list for the subscribed scope, not a diff; the app replaces its cache wholesale — `packages/server/src/terminal/terminal-session-controller.ts:404-421`.
  - `terminals_changed` also fans out on agent-attention transitions (`working`→`idle`), independent of title changes — `docs/terminal-activity.md:27`, `:33`.

### 2.3 `create_terminal_request` — open a shell

- **Name and purpose**: create a PTY terminal bound to a workspace/cwd.
- **Request**: `type: "create_terminal_request"` — `packages/protocol/src/messages.ts:3169-3188`. Fields: `cwd: string` (required), `workspaceId?: string`, `name?: string`, `agentId?: string`, `command?: string`, `args?: string[]`, `size?: { rows: number, cols: number }`, `requestId: string`. Notes: `size` was added in v0.1.107; the app no longer sends it (the PTY is sized by the pane-focus resize claim); daemons without it start at 80×24 and the first resize corrects it — comment inline at `packages/protocol/src/messages.ts:3176-3180`.
- **Response**: `create_terminal_response` — `packages/protocol/src/messages.ts:6826-6833`. Payload: `terminal: TerminalInfo | null`, `error: string | null`, `requestId: string`.
- **Capability gates**: none for the RPC itself. SDK workspace-terminal facade gates list/create on `features.workspaceTerminals` (see §1).
- **How the app/SDK uses it**: `daemon-client.createTerminal(cwd, name?, requestId?, { agentId?, command?, args?, workspaceId?, size? })` — `packages/client/src/daemon-client.ts:6758-6785`. The SDK's `terminals.create()` parses the terminal out of the response and throws when `terminal` is null — `packages/client/src/terminals/index.ts:133-151`. The daemon spawns the PTY in the detached terminal worker, not its own process; environment and `PASEO_CLI` path are baked at spawn time — `docs/terminal-worker.md:1-5`, `:17-18`.
- **Gotchas**:
  - The PTY outlives the daemon: restarts/upgrades/crashes keep terminals (subject to `keepTerminals` on the stop path and worker compatibility) — `docs/terminal-worker.md` (Desktop, Process model).
  - When `command` is set the terminal is born running that command; workspace scripts use the same spawn path with `command` set from `paseo.json` (§10).
  - `agentId` links the terminal to an agent (used by agent terminals); `isScript` is derived later, not settable here.
  - Creating with an explicit `size` is honored permanently for v0.1.107 clients — `packages/protocol/src/messages.ts:3176-3180`.

### 2.4 `terminal.rename.request` — rename

- **Name and purpose**: set a terminal's title (shown in tabs).
- **Request**: `type: "terminal.rename.request"` — `packages/protocol/src/messages.ts:3190-3194`. Fields: `terminalId`, `title: string`, `requestId`.
- **Response**: `terminal.rename.response` — `packages/protocol/src/messages.ts:6835-6842`. Payload: `requestId`, `success: boolean`, `error: string | null`.
- **Capability gates**: none.
- **How the app/SDK uses it**: `daemon-client.renameTerminal({ terminalId, title, requestId? })` — `packages/client/src/daemon-client.ts:6790-6802`. Title changes produce a terminal list snapshot via `terminalsChanged` but never touch workspace descriptors — `docs/terminal-activity.md:27`.
- **Gotchas**: renames are title-only; they do not change the PTY name used for script bookkeeping.

## 3. Subscribing to one terminal's output

### 3.1 `subscribe_terminal_request` — attach and get a slot

- **Name and purpose**: attach a viewer to a terminal's output stream. The daemon binds the viewer to a 1-byte **slot id**; from then on, output for this terminal arrives as binary frames carrying that slot.
- **Request**: `type: "subscribe_terminal_request"` — `packages/protocol/src/messages.ts:3224-3240`. Fields: `terminalId: string`, `requestId: string`, `restore?: { mode: "live" | "visible-snapshot" | "full-snapshot", scrollbackLines?: number, size?: { rows: number, cols: number } }`.
- **Response**: `subscribe_terminal_response` — `packages/protocol/src/messages.ts:6844-6860`. Payload is a discriminated union:
  - success branch: `terminalId`, `slot: int 0-255`, `subscriptionId?: string`, `error: null`, `requestId`;
  - failure branch: `terminalId`, `error: string`, `requestId`.
- **Binary frames** (after success): `slot` is used in the 1-byte slot field of every subsequent binary frame for this subscription — see §4. Layout bytes are `packages/protocol/src/binary-frames/terminal.ts:77-103`.
- **Capability gates**: the *attach* itself is unguarded, but terminal surfaces in the app require `features["terminal-restore-modes"] === true` before they even send the subscribe — `app/components/terminal-pane.tsx:299-302`, `app/terminal/runtime/terminal-restore-options.ts:14-16`. The daemon's delivery of the replay branches on `terminal_chunked_replay` (§1, §5.4). If `restore.size` is present and the source is a legacy (non-owned-subscriptions) slot, the daemon applies it as a size claim before binding the stream — `packages/server/src/terminal/terminal-session-controller.ts:745-755`. Slot exhaustion (256 concurrent streams) fails with `"No terminal stream slots available"` — `packages/server/src/terminal/terminal-session-controller.ts:43`, `:760-778`.
- **How the app/SDK uses it**: `daemon-client.observeTerminal(terminalId, receive, { restore?, signal?, requestId? })` — `packages/client/src/daemon-client.ts:6808-6872`. Key behaviors:
  - The default `restore` is `{ mode: "full-snapshot" }` — `packages/client/src/daemon-client.ts:6823`. (Note: explicit SDK callers may pass any mode; `observeTerminal` is the supported path — `observeTerminal` docstring at `:6802-6807` says replay begin/data/end arrive in `receive` and `terminal_stream_exit` detaches the slot and releases automatically.)
  - The subscription is an owned subscription; on success the payload's `slot` + `subscriptionId` are registered in a `TerminalStreamRouter` — `packages/client/src/daemon-client.ts:6840-6852`, `packages/client/src/terminal-stream-router.ts:27-46`, and `observe`/`release` go through `subscription.release.request` (§2.2).
  - The app sends `restore: { mode: "visible-snapshot", scrollbackLines, size }` once its measured grid is known (throws when restore-modes is unsupported) — `app/terminal/runtime/terminal-restore-options.ts:18-22`, invoked from `app/components/terminal-pane.tsx:598-611`. The pane is told to attach only after the native view reports ready with a measured size — `docs/terminal-rendering.md:15`.
  - On `terminal_stream_exit` the stream detaches and calls `receive` no more — `app/terminal/runtime/terminal-stream-controller.ts:90-98`.
- **Gotchas**:
  - `slot` is per-connection; slot ids may be reused across different connections for different terminals. Keep a `Map<slot, subscriptionId>` per socket.
  - `slot: 0-255` is enforced by the schema — `packages/protocol/src/messages.ts:6849`.
  - Legacy (non-`owned_subscriptions`) sources get slot `legacySlot` bookkeeping; modern sources must use the server-assigned `subscriptionId` for teardown (§2.2).
  - `restore.mode: "live"` means no replay at all — the viewer attaches to subsequent output only — `packages/server/src/terminal/terminal-restore.ts:43-45`.
  - Live output that arrives while the replay is in flight is **buffered** per stream (up to 4 MiB / `MAX_CLIENT_BUFFERED_BYTES`) and flushed after the snapshot cut, skipping revisions already present in the replay — `packages/server/src/terminal/terminal-session-controller.ts:990-1011` (buffering + overflow → `terminal_stream_exit` "Terminal replay live tail exceeded the buffer"), `:1145-1160` (dedup + preamble ordering).
  - Old ANSI hosts (no `terminal-restore-modes`): the app throws the localized "Update the host to view terminals" error instead of attaching — `app/terminal/runtime/terminal-restore-options.ts:14-16`.

### 3.2 Unsubscribing

- **Request** (legacy path only): `unsubscribe_terminal_request` — `packages/protocol/src/messages.ts:3242-3245`. Fields: `terminalId`. **No `requestId`, no response message.** Server releases the legacy slot `terminal-output:<id>` — `packages/server/src/terminal/terminal-session-controller.ts:225-227`.
- **Modern path**: `subscription.release.request` with the `subscriptionId` from the subscribe response — `packages/protocol/src/messages.ts:3402-3410`; modern sources that try `unsubscribe_terminal_request` get a thrown error server-side — `packages/server/src/server/session/owned-subscriptions/index.ts:391-398`. The SDK never sends `unsubscribe_terminal_request`; it releases through `OwnedSubscription.release()` — `packages/client/src/daemon-client.ts:1401-1413`.
- **How the app/SDK uses it**: `observeTerminal` handles teardown internally — on `terminal_stream_exit` it detaches the slot and aborts the subscription — `packages/client/src/daemon-client.ts:6854-6868`. Disconnecting the socket (app backgrounding, host switch) releases everything implicitly.

## 4. Binary frame formats (every frame a client must decode or send)

### 4.0 Common layout

All terminal-stream frames share one header, encode/decode at `packages/protocol/src/binary-frames/terminal.ts:16-33` (opcodes), `:77-88` (encode), `:90-103` (decode):

```
+--------+-------+----------------------+----------------------+
| opcode | slot  | payload              | (total = 2 + len)    |
| 1 byte | 1 B   | len(bytes) - 2 bytes |                      |
+--------+-------+----------------------+----------------------+
```

- `opcode`: one of the values in the table below. Unknown opcodes are rejected by `decodeTerminalStreamFrame` (returns `null`) — `packages/protocol/src/binary-frames/terminal.ts:64-75`, `:90-103`.
- `slot`: `0-255`, masked with `& 0xff` on encode — `packages/protocol/src/binary-frames/terminal.ts:85`. `0` is not reserved.
- `payload`: raw bytes, UTF-8 for text, JSON for structured payloads.

Binary frames are demultiplexed from file-transfer, plugin, diff, host-route frames by opcode ranges — `packages/protocol/src/binary-frames/demux.ts:20-52`. Terminal opcodes occupy `0x01-0x08` (specified here); chunked-transport reserves `0x31`; plugin frames use `0x20-0x2f` (`0x20` event, `0x21` output); diff frames use `0x40-0x4f` — see `packages/protocol/src/binary-frames/plugin.ts:9-12`, `diff.ts:3`.

The architecture doc's description of this framing matches the code — `docs/architecture.md:313-321`.

### 4.1 Opcode table and byte layouts

| Opcode | Name | Direction | Payload bytes | Schema / builder |
|---|---|---|---|---|
| `0x01` | `Output` | daemon → client | raw PTY/ANSI bytes (uninterpreted) | encoded at `packages/server/src/terminal/terminal-session-controller.ts:960-965`; routed at `packages/client/src/terminal-stream-router.ts:65-66` |
| `0x02` | `Input` | client → daemon | UTF-8 input bytes | daemon decodes with `Buffer.from(payload, "utf8")` — `packages/server/src/terminal/terminal-session-controller.ts:253-264`. **First-party clients never send this** (see §6.1) |
| `0x03` | `Resize` | client → daemon | UTF-8 JSON `{ rows: int>0, cols: int>0, intent?: "claim" \| "update" }` | `TerminalStreamResizeSchema` — `packages/protocol/src/binary-frames/terminal.ts:10-14`; consumed at `packages/server/src/terminal/terminal-session-controller.ts:266-277`. **First-party clients never send this** (see §6.3) |
| `0x04` | `Snapshot` | daemon → client (legacy) | UTF-8 JSON `TerminalState` (`encodeTerminalSnapshotPayload`) | `packages/protocol/src/binary-frames/terminal.ts:69`, `:105-117`. **No daemon code path emits Snapshot frames anymore** — the only producers are tests; clients count/display them for metrics only — `packages/client/src/daemon-client.ts:7386-7387`. "JSON snapshot frames have no rendering runtime" — `docs/protocol-compatibility.md:65-66` |
| `0x05` | `Restore` | daemon → client | complete ANSI replay as one byte blob | legacy only: coalesced by `createTerminalRestoreDelivery` when the client lacks `terminal_chunked_replay` — `packages/server/src/terminal/terminal-restore.ts:57-83`; the SDK normalizes it into begin/data/end events — `packages/client/src/terminal-stream-router.ts:67-75` |
| `0x06` | `ReplayBegin` | daemon → client | UTF-8 JSON `{ rows: int>0, cols: int>0, retainedHistoryLines: int>=0 }` | `TerminalReplayMetadataSchema` — `packages/protocol/src/binary-frames/terminal.ts:4-8`; wire payload built at `packages/server/src/terminal/terminal-restore.ts:91-98`; parsed at `packages/client/src/terminal-stream-router.ts:76-85` |
| `0x07` | `ReplayData` | daemon → client | ANSI bytes, ≤ 64 KiB per chunk | `TERMINAL_REPLAY_CHUNK_BYTES = 64 * 1024` — `packages/server/src/terminal/terminal-replay.ts:24`; encoded at `packages/server/src/terminal/terminal-restore.ts:99-102`; routed at `packages/client/src/terminal-stream-router.ts:87-88` |
| `0x08` | `ReplayEnd` | daemon → client | empty | encoded at `packages/server/src/terminal/terminal-restore.ts:100-102`; routed at `packages/client/src/terminal-stream-router.ts:89-90` |

`TerminalStateSchema` (Snapshot payload body): `rows`, `cols`, `grid: Cell[][]`, `scrollback: Cell[][]`, `cursor { row, col, hidden?, style?: "block"|"underline"|"bar", blink? }`, optional `title`, and optional per-row `gridWrapped`/`scrollbackWrapped` flags (only to `terminal_reflowable_snapshot` clients) — `packages/protocol/src/messages.ts:6790-6804`. Cells carry `char` plus optional `fg/bg/fgMode/bgMode/bold/italic/underline/dim/inverse/strikethrough` — `packages/protocol/src/messages.ts:6766-6779`.

### 4.2 Chunked-transport frame (opcode `0x31`, connection-scoped)

When both peers negotiated `binary_chunking_v1` (§1), messages bigger than the transport's plaintext frame budget are split into ordered chunks. Layout from `packages/protocol/src/chunked-transport.ts:8-9` (opcode/header consts), `:106-128` (sender), `:143-191` (receiver), `docs/protocol-compatibility.md:76-81`:

```
+------+---------+-------+---------+-------------------+-------------------+
| 0x31 | version | kind  |  flags  | slice bytes       | (total = 4 + n)   |
| 1 B  | 1 byte  | 1 B   | 1 byte  | n bytes           |                   |
+------+---------+-------+---------+-------------------+-------------------+
  version = 1             kind: 0 = text (original frame was a JSON/string frame),
                                1 = binary (original frame was bytes)
  flags (bitmask): bit0 (0x01) = START, bit1 (0x02) = END. Middle chunks: 0.
```

- No total length and no chunk count; receivers buffer slices incrementally — `docs/protocol-compatibility.md:78-80`.
- Reassembler enforces: exactly one START, matching `kind` across chunks, flags mask `& ~3 == 0`, cumulative size ≤ `MAX_WEBSOCKET_MESSAGE_BYTES` (100 MiB), UTF-8 decode only after `END`, transfers cannot interleave, and disconnect clears partial state — `packages/protocol/src/chunked-transport.ts:146-191`, `packages/protocol/src/websocket-message-limit.ts:2`.
- The sender waits for drain between chunks; ordinary messages keep the existing delivery path; slow-client protections count queued messages behind an active transfer — `docs/protocol-compatibility.md:83-87`.
- **Native clients disable outbound chunking** (React Native's WebSocket cannot wait for native drain; Android's OkHttp closes above 16 MiB queued). Inbound chunking stays enabled — `docs/protocol-compatibility.md:89-94`. A native iOS client that cannot report queued bytes should not enable `binary_chunking_v1` for sends it cannot pace; inbound must still be handled.
- The framing module never selects an encryption construction; the relay encrypts the opaque frames — `docs/protocol-compatibility.md:87`.

### 4.3 What the iOS client actually has to implement

Decode: `0x01` (feed bytes straight into SwiftTerm), `0x06`/`0x07`/`0x08` (replay into SwiftTerm, see §5), tolerate `0x05` (legacy hosts) and `0x04` (metrics-ignore), and `0x31` if it enabled `binary_chunking_v1`. Send: only JSON (`terminal_input`, see §6) unless it also wants to support the binary `0x02`/`0x03` paths — `packages/server/src/terminal/terminal-session-controller.ts:242-278` accepts both, but nothing first-party uses them, and the docs describe the binary path as the terminal stream protocol (`docs/architecture.md:313-321`).

## 5. ANSI restore/replay — the "modern terminal format" end to end

### 5.1 Restore modes on `subscribe_terminal_request`

`restore` (optional) — `packages/protocol/src/messages.ts:3228-3239`:

| `mode` | Wire meaning | Daemon behavior |
|---|---|---|
| `"live"` | no replay | `resolveTerminalRestoreSnapshotOptions` returns `null`; viewer gets subsequent output only — `packages/server/src/terminal/terminal-restore.ts:43-45` |
| `"visible-snapshot"` | replay + recent scrollback | `scrollbackLines` defaults to **200** (`DEFAULT_VISIBLE_RESTORE_SCROLLBACK_LINES`) — `packages/server/src/terminal/terminal-restore.ts:19`, `:49`; for older ANSI hosts (not `terminal_chunked_replay`) capped at **500** (`MAX_VISIBLE_RESTORE_SCROLLBACK_LINES`) — `packages/server/src/terminal/terminal-restore.ts:20`, `:49-54` |
| `"full-snapshot"` | replay + everything the worker retained | chunked hosts: `{ scrollbackLines }` passed through as-is (may be `undefined` = unlimited) — `packages/server/src/terminal/terminal-restore.ts:46-48`; non-chunked hosts: `undefined` options (all retained history) — same lines |

Backpressure re-sync (stream fell > 256 KiB behind **and** transport reports > 4 MiB queued) sends at most **500** recent rows plus the screen via `visible-snapshot` — `packages/server/src/terminal/terminal-restore.ts:24-34`, applied at `packages/server/src/terminal/terminal-session-controller.ts:1056-1060`, constants at `packages/server/src/terminal/terminal-restore.ts:10-20` (with `MAX_TERMINAL_OUTPUT_FRAME_BYTES = 256 * 1024` at `:10` and `MAX_CLIENT_BUFFERED_BYTES = 4 * 1024 * 1024` at `:17`); threshold checks at `packages/server/src/terminal/terminal-session-controller.ts:950-958`. The explicit subscription demand is preserved — a later attach/reconnect still requests the full configured history — `docs/terminal-performance.md:30`.

### 5.2 What the worker retains and emits

- The worker retains a fixed **10,000 history rows** plus the screen in its headless xterm; replay is serialized with `@xterm/addon-serialize` 0.14 against headless xterm 6 — `docs/terminal-worker.md:18`.
- A replay request emits begin metadata (dimensions, retained history, revision and input modes), at most **64 KiB per data chunk** (`TERMINAL_REPLAY_CHUNK_BYTES`), then end. Live output keeps flowing independently during replay — `docs/terminal-worker.md:54`, chunk size at `packages/server/src/terminal/terminal-replay.ts:24`.
- The wire `ReplayBegin` payload carries **only** `rows`, `cols`, `retainedHistoryLines` — `packages/server/src/terminal/terminal-restore.ts:91-98`. Revision, capture-time input modes and the ANSI replay preamble stay server-side (`TerminalReplayMetadata` at `packages/server/src/terminal/terminal-replay.ts:12-18`); the preamble reaches the client as an ordinary `Output` frame emitted before the buffered live bytes — `packages/server/src/terminal/terminal-session-controller.ts:1146-1154`.
- The serializer boundary owns cursor position, cursor visibility and explicit program-selected presentation; unset program styles leave the client's cursor defaults intact. It also restores SGR mouse encoding (tracking preserved, encoding otherwise omitted → legacy wheel reports) — `docs/terminal-worker.md:18`.

### 5.3 `Restore` (0x05) vs `ReplayBegin`/`ReplayData`/`ReplayEnd`

The daemon's only old-app adapter is `createTerminalRestoreDelivery` — `packages/server/src/terminal/terminal-restore.ts:65-104`:

- **Chunked client** (`terminal_chunked_replay` advertised): each worker event becomes one frame — begin (JSON metadata) → `0x06`, data → `0x07`, end → `0x08` — `packages/server/src/terminal/terminal-restore.ts:85-103`.
- **Legacy client**: all data events are buffered, then one `Restore` (`0x05`) frame carries the whole ANSI blob — `packages/server/src/terminal/terminal-restore.ts:71-83`. Wire compatibility requirement: app **v0.1.81+**; earlier apps omit `restore` and reject `0x05` — `docs/protocol-compatibility.md:57-60`.
- The SDK keeps the established subscribe request against older ANSI hosts and normalizes a single `Restore` into begin/data/end events with empty metadata (`{ type: "begin" }`, no rows/cols) — `packages/client/src/terminal-stream-router.ts:67-75`. Never concatenate capable replay chunks to feed the renderer; each chunk must be parsed incrementally — `docs/terminal-performance.md:22`.

### 5.4 End-to-end sequence (chunked client)

1. Client sends `subscribe_terminal_request` with `restore: { mode: "visible-snapshot", scrollbackLines, size? }` — schema `packages/protocol/src/messages.ts:3224-3240`.
2. Server sends `subscribe_terminal_response` `{ slot, subscriptionId, error: null, requestId }` — `packages/server/src/terminal/terminal-session-controller.ts:780-790`, schema `packages/protocol/src/messages.ts:6844-6860`.
3. Worker captures the screen; daemon emits `ReplayBegin` (JSON `{rows, cols, retainedHistoryLines}` — `packages/server/src/terminal/terminal-restore.ts:91-98`).
4. Daemon emits zero or more `ReplayData` (≤ 64 KiB ANSI) — `packages/server/src/terminal/terminal-replay.ts:32-34`, `packages/server/src/terminal/terminal-restore.ts:99-102`.
5. Daemon emits `ReplayEnd` — `packages/server/src/terminal/terminal-restore.ts:100-102`.
6. Delivery branch decision is made **per subscription at replay time**, not at subscribe time — `packages/server/src/terminal/terminal-session-controller.ts:1111-1120`.
7. Before buffered live bytes resume, the daemon emits the replay preamble (input modes) through the output coalescer — `packages/server/src/terminal/terminal-session-controller.ts:1146-1154`.
8. `Output` frames resume; any buffered output whose `revision <= replay.revision` is dropped — `packages/server/src/terminal/terminal-session-controller.ts:1151-1162`; docs: "Coalesced output carries the LAST chunk's revision" — `docs/terminal-performance.md:28`. Live output never waits for app delivery; a failed replay affects only that viewer — `docs/terminal-performance.md:26`.
9. On replay failure for legacy sources the daemon keeps the stream attached and retries on the next snapshot notification; for capable sources it emits `terminal_stream_exit` with `payload.error` — `packages/server/src/terminal/terminal-session-controller.ts:1075-1102`.

### 5.5 Renderer obligations for SwiftTerm

- Parse replay bytes as a stream; do **not** rebuild the whole scrollback as one string write. The web/native renderers use xterm with grapheme widths (`@xterm/addon-unicode-graphemes` ≥ 0.5.0-beta.330) — a SwiftTerm client must pick a consistent width table or the cursor after disputed clusters lands inside the wrong cell — `docs/terminal-rendering.md:19`, `:27`.
- The daemon answers cursor-position reports (`CSI 6n`) from its buffer; a client re-parses the daemon's ANSI replay with its own table — a mismatch moves the cursor — `docs/terminal-rendering.md:23`.
- Daemons advertising `features["terminal-grapheme-widths"]` use grapheme widths; otherwise the app keeps each renderer's previous table — `docs/terminal-rendering.md:23`.
- Each renderer suppresses generated replies while parsing replay — `docs/terminal-performance.md:22`. (SwiftTerm has automatic responses of its own; they must not fire during the replay pass.)
- Replay geometry belongs to the parser queue: apply the latest measured size **after** replay, **before** live bytes; a layout effect must not resize the renderer mid-replay — `docs/terminal-performance.md:27`. The pane attaches only with the view's measured size so the daemon replays at the client's size — `docs/terminal-rendering.md:15`.
- One renderer per workspace pane; hidden retained tabs keep streams, terminals in unfocused workspaces detach — `docs/terminal-performance.md:34`.
- `Snapshot`/`TerminalState` frames (0x04) and JSON-snapshot declarations are accepted on the wire but have **no rendering runtime** — `docs/protocol-compatibility.md:65-66`.

## 6. Sending input, keys, mouse, resize

### 6.1 Input (`terminal_input` + `input`)

- **Name and purpose**: send raw bytes/text to the terminal. This is a **text** session message, not a binary frame.
- **Request**: `type: "terminal_input"` — `packages/protocol/src/messages.ts:3264-3268`. Fields: `terminalId: string`, `message: { type: "input", data: string } | { type: "resize", rows, cols, intent? } | { type: "mouse", row, col, button, action }` — the discriminated union is `TerminalClientMessageSchema` at `packages/protocol/src/messages.ts:3247-3262`.
- **Response**: none (fire-and-forget). The daemon routes it straight to the PTY; there is no acknowledgement — `packages/server/src/terminal/terminal-session-controller.ts:227-230` (dispatch), `:795-810` (handling); the SDK facade notes "Does not await command execution" — `packages/client/src/terminals/index.ts:50`.
- **Capability gates**: none.
- **How the app/SDK uses it**: `daemon-client.sendTerminalInput(terminalId, message)` wraps it in `sendSessionMessage` — `packages/client/src/daemon-client.ts:6887-6889`; keystrokes and virtual-key-bar input go through `dispatchTerminalInputEntry` with `{ type: "input", data }` — `app/components/terminal-pane.tsx:683-714`, resize at `:905-937`; the new-workspace flow sends `\r` after the initial prompt — `app/screens/new-workspace-terminal.ts:35-50`, `:81`.
- **Gotchas**:
  - The daemon **also** accepts binary `0x02 Input` frames (UTF-8 bytes, empty payloads dropped) — `packages/server/src/terminal/terminal-session-controller.ts:253-264` — but no first-party client sends them; do not build a client that sends binary input unless you also handle legacy-slot edge cases (`slot` from the subscribe response is connection-local).
  - Standalone Ctrl-C/Escape input while terminal activity is `working` clears the activity without finished attention; exact-match only — `docs/terminal-activity.md:56-59`.
  - Input before attach completes is queued in the app (`pendingTerminalInputRef`) and flushed when `isAttaching` clears — `app/components/terminal-pane.tsx:716-735`.

### 6.2 Keys and modifiers

- **Encoding**: `encodeTerminalKeyInput(input, { inputMode })` in `packages/protocol/src/terminal-key-input.ts` produces escape sequences; modifier encoding depends on negotiated terminal modes — Kitty keyboard protocol when `kittyKeyboardFlags > 0` (`:45-54`), Win32 input mode when `win32InputMode` and a modifier is held (`:36-43`), xterm-style `CSI 1;<mod> <key>` otherwise. Win32 Enter uses `CSI 13;28;13;1;<cs>;1_` — `:54-58`.
- **Mode tracking**: `TerminalInputModeTracker` (`packages/protocol/src/terminal-input-mode.ts:62+`) tracks Kitty flags, Win32 mode, application cursor keys, bracketed paste from program output; it must run **once per process boundary** (worker authoritative, daemon caches) — `docs/terminal-performance.md:29`. The wire never announces input modes; the client infers them from the bytes it parses.
- **How the app uses it**: virtual key bar + physical keyboard route through `dispatchTerminalKeyInput` with the emulator's current `inputMode` — `app/terminal/runtime/terminal-key-dispatch.ts:46-53`, key set at `:18-28`. The SDK offers `sendKeys(["Enter", ...])` with a fixed token table (Enter→`\r`, BSpace→`\x7f`, C-c→`\x03`, …) — interface at `packages/client/src/terminals/index.ts:53`, implementation at `packages/client/src/terminals/index.ts:120`, token table at `packages/client/src/terminals/index.ts:152-179`.
- **Gotchas**:
  - Generated replies must be suppressed while parsing replay or the program sees phantom cursor-position reports — `docs/terminal-performance.md:22`.
  - Escape-sequence pasted content is excluded from the Ctrl-C activity fallback — `docs/terminal-activity.md:57-59`.
  - `dispatchTerminalKeyInput` emits only when `encoded.length > 0`; unmapped keys produce nothing — `app/terminal/runtime/terminal-key-dispatch.ts:50-55`.

### 6.3 Resize — `claim` / `update` and PTY size ownership

- **Wire shapes** (two):
  - JSON: `terminal_input` with `message: { type: "resize", rows, cols, intent? }` — `packages/protocol/src/messages.ts:3247-3257`.
  - Binary: `Resize` (0x03) with payload JSON `{ rows, cols, intent? }` — `packages/protocol/src/binary-frames/terminal.ts:10-14`; accepted daemon-side at `packages/server/src/terminal/terminal-session-controller.ts:266-277`.
- **Semantics** — `packages/server/src/terminal/terminal-size-ownership.ts:1-38`:
  - `intent: "claim"` (or missing intent — legacy) **transfers** PTY-size ownership to this connection, even when dimensions are unchanged.
  - `intent: "update"` applies only from the current owner; other connections are ignored.
  - Only an actual size change is forwarded to the PTY.
- **Who claims**: focus and direct interaction send `claim`; later geometry changes from that same connection send `update` — `docs/terminal-performance.md:35`. Passive rendering work (attach, visibility, font settling, refits, idle looking) must not send resize — `docs/architecture.md:321`. The pane-focus claim path decides claim vs update vs nothing — `app/components/terminal-pane.tsx:905-927` (`resolveTerminalResizeClaim`, readiness includes workspace focus, pane focus, app visible, client ready, connected, renderer ready).
- **Capability gates**: `terminal-size-ownership` (daemon feature) flips update handling from legacy claim-everyone to claim/update ownership — `packages/server/src/terminal/terminal-size-ownership.ts:31-38`; the app reads it at `app/components/terminal-pane.tsx:307-309`; the daemon advertises it at `packages/server/src/server/websocket-server.ts:2105-2106`; schema at `packages/protocol/src/messages.ts:3907`.
- **How the app/SDK uses it**: `sendTerminalInput(terminalId, { type: "resize", rows, cols, intent })` — `app/components/terminal-pane.tsx:905-937`; claimed resizes are also sent when attaching if a preferred size is known — `app/terminal/runtime/terminal-stream-controller.ts:72-79`; debounced via `TerminalResizeDebouncer` — `app/components/terminal-pane.tsx:937-947`; the legacy restore path can also carry `restore.size` in the subscribe request (§3.1).
- **Gotchas**:
  - Without `terminal-size-ownership`, **every** resize from **any** connection steals the PTY size (legacy behavior) — `packages/server/src/terminal/terminal-size-ownership.ts:31-38`.
  - The server does not broadcast resize ownership; every attached client renders the PTY's output in its own viewport — `docs/architecture.md:321`.
  - The resized PTY redraws through normal output; there is no `resize_done` message.
  - A resize from a non-owning connection is silently ignored — no error frame.

### 6.4 Mouse

- `message: { type: "mouse", row, col, button, action: "down" | "up" | "move" }` inside `terminal_input` — `packages/protocol/src/messages.ts:3258-3261`.
- The daemon forwards it to the session like any other message (`session.send(msg.message)`) — `packages/server/src/terminal/terminal-session-controller.ts:810`. Input modes distinguish legacy vs SGR mouse encoding; the worker tracks the mouse encoding mode as part of input modes and restores it in replay preambles — `docs/terminal-worker.md:18`.

## 7. Killing a terminal

- **Name and purpose**: destroy the PTY and retire the terminal.
- **Request**: `type: "kill_terminal_request"` — `packages/protocol/src/messages.ts:3270-3274`. Fields: `terminalId`, `requestId`.
- **Response**: `kill_terminal_response` — `packages/protocol/src/messages.ts:6862-6869`. Payload: `terminalId`, `success: boolean`, `requestId`.
- **Capability gates**: none.
- **How the app/SDK uses it**: `daemon-client.killTerminal(terminalId, requestId?)` — `packages/client/src/daemon-client.ts:6891-6905`. The SDK facade `terminals.kill()` throws when `success` is false — `packages/client/src/terminals/index.ts:125-130`. The daemon detaches all stream registrations (emitting `terminal_stream_exit`) before killing — `packages/server/src/terminal/terminal-session-controller.ts:813-841`. The app's script-stop path kills the backing terminal — `app/screens/workspace/scripts/use-workspace-script-actions.ts:118-132`.
- **Gotchas**:
  - Killing detaches and releases the viewer streams; a slow viewer gets `terminal_stream_exit` either way (clean or `error`) — `packages/server/src/terminal/terminal-session-controller.ts:1197-1213`.
  - Worker compatibility: terminals held by an incompatible worker cannot be listed/created/killed via normal RPCs; `list_terminals`/`create_terminal` answer `rpc_error` `terminal_worker_incompatible` — `docs/terminal-worker.md` (Protocol versions). If no compatible worker exists, kill cannot reach the terminal — the daemon reports it with `success: false` — `packages/server/src/terminal/terminal-session-controller.ts:818-841`.
  - `terminal_stream_exit` with `payload.error` means **observation failure**, not PTY exit — the process may keep running — `packages/protocol/src/messages.ts:6886`.
  - `close_items_request` offers a bulk kill path (`terminalIds: string[]`) with the same semantics — `packages/protocol/src/messages.ts:1008`, client at `packages/client/src/daemon-client.ts:6907-6923`.

## 8. Capture

- **Name and purpose**: read the terminal's text content (rows) for copy/paste, CLI `paseo terminal capture`, scrollback export. Capture is synchronous with PTY callbacks; the worker flushes the output coalescer before the cut so a later batch never includes bytes already in the capture — `docs/terminal-worker.md:54`.
- **Request**: `type: "capture_terminal_request"` — `packages/protocol/src/messages.ts:3276-3284`. Fields: `terminalId`, `start?: int`, `end?: int`, `stripAnsi?: boolean = true` (default), `requestId`.
- **Response**: `capture_terminal_response` — `packages/protocol/src/messages.ts:6871-6879`. Payload: `terminalId`, `lines: string[]`, `totalLines: int >= 0`, `requestId`. On missing manager/terminal/error: `lines: []`, `totalLines: 0` (never an error response) — `packages/server/src/terminal/terminal-session-controller.ts:842-901`.
- **Capability gates**: none.
- **How the app/SDK uses it**: `daemon-client.captureTerminal(terminalId, { start?, end?, stripAnsi? }, requestId?)` — `packages/client/src/daemon-client.ts:6925-6946`; SDK `terminals.capture()` passes through — `packages/client/src/terminals/index.ts:37-44`, `:121-124`; CLI `paseo terminal capture` — `docs/architecture.md:171`.
- **Gotchas**:
  - `stripAnsi: true` is the **default** (`.default(true)` — the wire-level default applies on strict parse) — `packages/protocol/src/messages.ts:3281`.
  - `start`/`end` are absolute line indexes into the retained buffer, not "last N"; negative-index semantics are not defined in the schema.
  - The worker retains 10,000 history rows + screen; capture beyond that range silently returns what exists — `docs/terminal-worker.md:18`.
  - Text capture translates only the requested rows; no cell grid is rebuilt — `docs/terminal-performance.md:23`.

## 9. Terminal activity indicators

### 9.1 Wire surface

Three messages carry activity to clients:

1. **`TerminalInfo.activity`** on terminal listings/snapshots: `activity?: TerminalActivity | null` — `packages/protocol/src/messages.ts:6763`. `TerminalActivitySchema` — `packages/protocol/src/terminal-activity.ts:9-17`:
   ```json
   { "state": "idle" | "working" | "attention",
     "attentionReason": "finished" | "needs_input" | null | undefined,
     "changedAt": <number> }
   ```
   Forward-compatible by `.catch()`: unknown states degrade to `idle`, unknown reasons to `null` — `packages/protocol/src/terminal-activity.ts:11-15`.
2. **`terminals_changed`** pushes — the activity rides the same snapshot as `TerminalInfo` — `packages/protocol/src/messages.ts:6815-6824`.
3. **`terminal_attention_required`** — server-initiated attention notification — `packages/protocol/src/messages.ts:6891-6904`. Payload: `subscriptionId?`, `serverId?`, `terminalId`, `cwd`, `workspaceId?`, `reason: "finished" | "needs_input"`, `title: string`, `body: string`, `shouldNotify: boolean`.
4. (Related) **`terminal_stream_exit`** — not activity, but the "update the row" signal for tab state — `packages/protocol/src/messages.ts:6881-6889`.

### 9.2 Producing side (hook reporting)

Activity is produced **outside** terminal stream parsing. Agent hook commands report coarse states to the daemon's local `/api/terminal-activity` endpoint; the tracker is source-agnostic — `docs/terminal-activity.md:7-9`. The shell gets four env vars at creation: `PASEO_TERMINAL_ID`, `PASEO_ACTIVITY_TOKEN`, `PASEO_TERMINAL_ACTIVITY_URL`, `PASEO_HOOK_CLI` — `docs/terminal-activity.md:41-46`. Claude mapping: `UserPromptSubmit`→`running`, `Stop`/`StopFailure`/`SessionEnd`→`idle`, `Notification(idle_prompt)`→`needs-input` — `docs/terminal-activity.md:50-56`; Codex mapping at `docs/terminal-activity.md:61-66`; OpenCode via a server plugin at `docs/terminal-activity.md:68-79`. Daemon maps hook states onto terminal activity: `running`→`state: working`, `idle`→`state: idle`, `needs-input`→`state: idle` + `attentionReason: needs_input`; a `working`→`idle` transition records `attentionReason: finished` until the user focuses the terminal — `docs/terminal-activity.md:81`.

### 9.3 Subscription semantics and app handling

- `terminal_attention_required` is delivered to any socket whose session event subscription includes `"terminal_attention_required"` — `SessionEventSubscriptionSchema` at `packages/protocol/src/messages.ts:3359-3377` (member at `:3370`). The app observes it via `observeEvents(["terminal_attention_required"])` and routes it to notifications — `app/contexts/session-context.tsx:471`, `:644-650`; the app subscribes to `agent_attention_required` the same way.
- The daemon also fires a "Terminal finished" attention notification over the websocket layer — `docs/terminal-activity.md:33`. A terminal that exits while still `working` emits no turn-end notification — `docs/terminal-activity.md:33`.
- **Focus clears finished attention**: client heartbeats carry `focusedTerminalId` (nullable; COMPAT since v0.1.97, removed-optional-default after 2026-12-13). When a visible client focuses an attended terminal, the daemon clears the attention — `packages/protocol/src/messages.ts:3088-3097` (heartbeat schema at `:3088`), SDK sends it at `packages/client/src/daemon-client.ts:2534-2547`, app derives `focusedTerminalId` from the session store and heartbeats it at `app/contexts/session-context.tsx:223-252`, `docs/terminal-activity.md:83-86`.
- Status bucket derivation is shared protocol code: `deriveTerminalActivityStatusBucket(activity)` — `attentionReason === "needs_input"` → `needs_input`, `finished` → `attention`, `working` → `running`, idle → `null` — `packages/protocol/src/terminal-activity.ts:24-31`. The tab indicator uses it: `app/panels/terminal-panel.tsx:8`, `:76`.
- Terminal list visibility is `workspaceId`-scoped; unowned terminals fall back to path-prefix routing for status contribution only — `docs/terminal-activity.md:35-37`.

### 9.4 Gotchas

- Idle terminals contribute **no** workspace status — only `working` and attention transitions do — `docs/terminal-activity.md:81`.
- The tracker defaults to unknown (`null`); an absent `activity` field means "no hook data", not "idle".
- Workspace contribution (status rollup) is separate from the terminal list; a title-only change produces a list snapshot but never touches workspace descriptors — `docs/terminal-activity.md:27`.
- Hook installation is opt-in (`daemon.enableTerminalAgentHooks`, default `false`); without it terminals still work but emit no activity — `docs/terminal-activity.md:87-93`.
- SIGWINCH/focus/resize do not clear attention; only focusing does — `docs/terminal-activity.md:83-86`.

## 10. Workspace scripts

### 10.1 Configuration — `paseo.json` scripts

- Repo root `paseo.json` holds `scripts`: a record of name → entry — raw schema `PaseoScriptEntryRawSchema` (type/command/port, `.passthrough()`, unknown fields kept) at `packages/protocol/src/paseo-config-schema.ts:38-43`, record at `:74-78`, normalized by `getScriptConfigs` at `packages/server/src/utils/worktree.ts:319-355` (command must be a non-empty string; `type: "service"` + `port` picks up ServiceScriptConfig).
- **Plain script** (`type` absent): `{ "command": "npm run typecheck" }` — example in repo `paseo.json:28-30`.
- **Service script** (`type: "service"`): `{ "type": "service", "command": "...", "port": 3000? }` — `ServiceScriptConfig` at `packages/server/src/utils/worktree.ts:124-129`; `port` is an explicit override, otherwise auto-assigned from the configured range — `packages/server/src/utils/worktree.ts:345-352`, allocation via `servicePorts` in `worktree.servicePorts` or the global daemon config — `packages/server/src/server/daemon-config-store.ts:661-665`, allocator at `packages/server/src/server/workspace-service-port-allocator.ts`.
- Scripts spawn as **terminals** named after the script (`name`/`title` = scriptName) with injected env — `packages/server/src/server/worktree-bootstrap.ts:500-512`; env includes `HOST`, `PASEO_PORT` (assigned port), `PASEO_URL` (proxy URL), and `PASEO_SERVICE_<NAME>_PORT` / `PASEO_SERVICE_<NAME>_URL` for each peer service — `packages/server/src/server/workspace-service-env.ts:25-69`.
- Lifecycle entries: `{ lifecycle, exitCode, terminalId, type, workspaceId }` in the workspace runtime store feed `WorkspaceScriptPayload.lifecycle` (`running`|`stopped`) and `exitCode` — `packages/protocol/src/messages.ts:4220`, `:4231-4234`.
- Config parse failures abort the script RPC with the parse error — `packages/server/src/server/worktree-bootstrap.ts:537-540`.
- The config file is read fresh per script operation (no daemon reload needed); `PaseoConfigSchema` tolerates unknown keys and bad script entries by policy — `packages/protocol/src/paseo-config-schema.ts:74-101`.

### 10.2 `workspace.script.list.request` — list scripts with live state

- **Name and purpose**: list the configured scripts of a workspace with their runtime state, port, proxy URLs, health and backing terminal id.
- **Request**: `type: "workspace.script.list.request"` — `packages/protocol/src/messages.ts:3204-3208`. Fields: `workspaceId: string`, `requestId: string`. (Dotted namespace per `docs/rpc-namespacing.md` convention referenced at `docs/architecture.md:285`.)
- **Response**: `workspace.script.list.response` — `packages/protocol/src/messages.ts:4866-4869`. Payload `WorkspaceScriptOperationPayloadSchema` — `packages/protocol/src/messages.ts:4857-4864`: `requestId`, `workspaceId`, `scriptName?: string`, `script?: WorkspaceScriptPayload | null`, `scripts?: WorkspaceScriptPayload[]`, `error: string | null`.
- **`WorkspaceScriptPayload`** — `packages/protocol/src/messages.ts:4223-4234`: `scriptName`, `type: "script" | "service"` (default `"service"`), `hostname: string`, `port: int | null`, `localProxyUrl?: string | null`, `publicProxyUrl?: string | null`, `proxyUrl: string | null` (defaults to `null`), `lifecycle: "running" | "stopped"`, `health: "healthy" | "unhealthy" | null`, `exitCode?: number | null`, `terminalId?: string | null`.
- **Capability gates**: `features.workspaceScriptManagement` — schema `packages/protocol/src/messages.ts:4014`, daemon advertises at `packages/server/src/server/websocket-server.ts:2199-2201`; the CLI gates on it (`packages/cli/src/commands/script/shared.ts:17-20`). The app does **not** gate (it renders script rows when `workspace.scripts` is non-empty) — no code path checks the feature.
- **How the app/SDK uses it**: `daemon-client.listWorkspaceScripts(workspaceId, requestId?)` — `packages/client/src/daemon-client.ts:3246-3257`; the directory-sync layer calls it on demand when `script_status_update` activity is wanted, then folds the snapshot into the replica — `app/runtime/directory-sync/index.ts:342-353`. The CLI `paseo script ls` calls it — `docs/architecture.md:172`, `docs/service-proxy.md:33-39`. Scripts also appear in `WorkspaceDescriptorPayload.scripts` (default `[]`) — `packages/protocol/src/messages.ts:4302`, `:4361`.
- **Gotchas**:
  - The payload `hostname` for a service is the local proxy hostname (e.g. `dev--feature-auth--miniweb.localhost`) even when the script is stopped; `port` is `null` until assigned/running for auto-assigned services.
  - `health` is probed by the daemon's health monitor for services with a port; plain scripts report `health: null`.
  - Missing serviceProxy subsystem (or missing runtime store) yields `scripts: []` rather than an error — `packages/server/src/server/session/workspace-scripts/workspace-scripts-service.ts:114-118` (buildSnapshot guard) — list itself returns `error` only on thrown failures.

### 10.3 `workspace.script.start.request` — start a script

- **Name and purpose**: spawn a configured script as a supervised terminal and (for services) allocate a port and register the proxy route.
- **Request**: `type: "workspace.script.start.request"` — `packages/protocol/src/messages.ts:3210-3215`. Fields: `workspaceId`, `scriptName`, `requestId`.
- **Response**: `workspace.script.start.response` — `packages/protocol/src/messages.ts:4871-4874`; payload `WorkspaceScriptOperationPayloadSchema` (same shape as list; `scripts` carries the full refreshed list on success) — `packages/protocol/src/messages.ts:4857-4864`.
- **Legacy alias**: `start_workspace_script_request` → `start_workspace_script_response` — request `packages/protocol/src/messages.ts:3197-3202`, response `packages/protocol/src/messages.ts:4846-4855`. `daemon-client.startWorkspaceScript()` uses the **legacy** name; `startWorkspaceScriptWithStatus()` uses the dotted one — `packages/client/src/daemon-client.ts:3228-3244`, `:3259-3271`. Both run the same daemon path.
- **Capability gates**: same `workspaceScriptManagement` feature as list; the CLI gates — `packages/cli/src/commands/script/shared.ts:17-20`.
- **How the app/SDK uses it**: `use-workspace-script-actions` calls `client.startWorkspaceScript(workspaceId, scriptName)`; on success the returned `terminalId` is handed to the tab host to open the script terminal — `app/screens/workspace/scripts/use-workspace-script-actions.ts:71-101`. The daemon then (a) reads `paseo.json`, (b) for `service` scripts allocates a port, builds hostnames/URLs, registers the service-proxy route, computes env, (c) spawns the terminal, (d) records the runtime entry `{ lifecycle: "running", terminalId, exitCode: null }`, (e) publishes `script_status_update` to every client — `packages/server/src/server/worktree-bootstrap.ts:520-585`, `packages/server/src/server/session/workspace-scripts/workspace-scripts-service.ts:33-54`, `:136-155`.
- **Gotchas**:
  - Starting an already-running script fails with `Script '<name>' is already running` — `packages/server/src/server/worktree-bootstrap.ts:556-558`.
  - Service scripts get `PASEO_PORT`/`PASEO_URL`/peer `PASEO_SERVICE_*` env; plain scripts get **no** injected env — `packages/server/src/server/workspace-service-env.ts:36-39`.
  - Auto port assignment can come from `worktree.servicePorts` in `paseo.json` or the global daemon config (`daemon.worktrees.servicePorts`); explicit `port` wins — `packages/server/src/server/worktree-bootstrap.ts:560-585`.
  - `command` is interpreted by the default shell; the terminal outlives the daemon like any terminal.
  - MCP exposes `start_workspace_script` with the same semantics; it requires an explicit workspace id — `docs/service-proxy.md:39`.

### 10.4 `workspace.script.stop.request` — stop a script

- **Name and purpose**: stop a running script by terminating its supervised terminal (not merely removing the proxy route) — normal script lifecycle cleanup stays authoritative — `docs/service-proxy.md:39`.
- **Request**: `type: "workspace.script.stop.request"` — `packages/protocol/src/messages.ts:3217-3222`. Fields: `workspaceId`, `scriptName`, `requestId`.
- **Response**: `workspace.script.stop.response` — `packages/protocol/src/messages.ts:4876-4879`; payload `WorkspaceScriptOperationPayloadSchema`.
- **Capability gates**: `workspaceScriptManagement` as above.
- **How the app/SDK uses it**: `daemon-client.stopWorkspaceScript(workspaceId, scriptName, requestId?)` — `packages/client/src/daemon-client.ts:3273-3285`. Note: **the app does not call it** — stop stops the script by calling `client.killTerminal(terminalId)` on the backing terminal (find it via the script row's `terminalId`) — `app/screens/workspace/scripts/use-workspace-script-actions.ts:103-132`. Both paths converge on the same terminal kill, but only the RPC path also emits the `workspace.script.*.response` shape.
- **Gotchas**:
  - `stop` on a stopped or unknown script throws `Script '<name>' is not running`; the backing terminal must still exist — `packages/server/src/server/session/workspace-scripts/workspace-scripts-service.ts:216-227`.
  - Stopping the terminal flips the runtime entry to `lifecycle: "stopped"` and unregisters the service route; services then disappear from health monitoring — `packages/server/src/server/worktree-bootstrap.ts:588-605`.
  - Clients tracking `isScript` terminals (`TerminalInfo.isScript`) can correlate the script row with the terminal row — `packages/protocol/src/messages.ts:6757`, detector at `packages/server/src/server/session.ts:1193-1197`.

### 10.5 `script_status_update` — daemon-pushed script state

- **Name and purpose**: broadcast the full scripts array for a workspace on every change (start/stop/health/exit).
- **Frame**: `script_status_update` — `packages/protocol/src/messages.ts:4686-4694`. Payload: `subscriptionId?: string`, `workspaceId: string`, `scripts: WorkspaceScriptPayload[]`.
- **Subscription path**: it is a **connection event stream** member — `SessionEventSubscriptionSchema` at `packages/protocol/src/messages.ts:3366`; clients opt in with `session.events.set_subscription.request` — `packages/protocol/src/messages.ts:3380-3385`. The app does exactly that (`observeEvents(["script_status_update"])`) and keeps a per-directory demand counter so a visible workspace screen holds the subscription — `app/runtime/directory-sync/index.ts:323-344`.
- **How the app receives it**: the response carries `subscriptionId`; updates route by it; the directory replica applies the snapshot wholesale — `app/runtime/directory-sync/index.ts:335-341`.
- **Gotchas**:
  - Broadcast to **all** clients of the host when not using owned subscriptions; with `owned_subscriptions`, only subscribers get it — `packages/server/src/server/session/workspace-scripts/workspace-scripts-service.ts` ("Script status is daemon state, so it reaches every client, not only the requester" — comment at `:68`), `packages/server/src/server/session/owned-subscriptions/index.ts` (send gating).
  - The authoritative snapshot after any RPC (`list`/`start`/`stop`) is in the RPC response; treat `script_status_update` as the sync-back for other clients.
  - `workspace.scripts` in `WorkspaceDescriptorPayload` is the same projection read at fetch time — `packages/protocol/src/messages.ts:4361`.

### 10.6 Proxy URLs and hostnames

Generated hostname: `<script>--<branch>--<project>.localhost`, with the branch segment omitted on `main`/`master` — `docs/service-proxy.md:11-19`. The combined leftmost label is capped at 63 chars with a deterministic `--<8-hex-sha256-prefix>` hash suffix — `packages/server/src/server/service-proxy.ts:124-140`, docs `docs/service-proxy.md:27`. Label chars are `a-z0-9-`, a leading title-case/space/underscore collapses to `-`, empty → `untitled` — `packages/server/src/server/service-proxy.ts:99-122`. Public aliases use the same label under `<publicBaseUrl>`'s hostname — `packages/server/src/server/service-proxy.ts:149-160`.

Local and public URL computation — `projectServiceProxyUrls` at `packages/server/src/server/service-proxy.ts:175-208`:

- `localProxyUrl = http://<label>.localhost:<daemonPort>` (null when the daemon has no TCP listener) — `:182-185`.
- `publicProxyUrl = <publicBaseUrl protocol>//<label>.<publicBaseUrl host><optional port>` (null when `publicBaseUrl` unset) — `packages/server/src/server/service-proxy.ts:186-195`.
- `proxyUrl = publicProxyUrl ?? localProxyUrl` — `:196-201`.
- `hostname` in the payload is the local label hostname — `:205-212`.
- The payload's `proxyUrl` is what the app shows when no route preference is set; the app derives `localProxyUrl`/`publicProxyUrl` from the payload with a legacy fallback for old hosts (`isLocalOnlyUrl(proxyUrl)` heuristic) — `app/utils/workspace-script-links.ts:81-89`.

Service-only reachability: `serviceProxy.listen` starts a separate service-only listener; `publicBaseUrl` adds public aliases; localhost proxying is always enabled — `docs/service-proxy.md:41-60`, env vars `PASEO_SERVICE_PROXY_LISTEN` / `PASEO_SERVICE_PROXY_PUBLIC_BASE_URL` (env wins over config) — `docs/service-proxy.md:133-141`, `docs/service-proxy.md:7`. Route lookup normalizes the port away; the forwarded authority is not authenticated — `docs/service-proxy.md:127-132`.

Daemon registers the route before spawning the terminal; route is removed when the script terminal exits — `packages/server/src/server/worktree-bootstrap.ts:563-581`, `:588-605`.

## 11. Operation index (machine-checkable)

| Operation | Wire type | Kind | Cite |
|---|---|---|---|
| list terminals | `list_terminals_request` → `list_terminals_response` | JSON RPC | `packages/protocol/src/messages.ts:3149`, `:6806` |
| subscribe terminals (directory) | `subscribe_terminals_request` → `terminals_changed` push | JSON + push | `packages/protocol/src/messages.ts:3156`, `:6815` |
| unsubscribe terminals (legacy) | `unsubscribe_terminals_request` | JSON, no reply | `packages/protocol/src/messages.ts:3163` |
| create terminal | `create_terminal_request` → `create_terminal_response` | JSON RPC | `packages/protocol/src/messages.ts:3169`, `:6826` |
| rename terminal | `terminal.rename.request` → `terminal.rename.response` | JSON RPC | `packages/protocol/src/messages.ts:3190`, `:6835` |
| attach to terminal output | `subscribe_terminal_request` → `subscribe_terminal_response` + binary frames | JSON RPC + binary | `packages/protocol/src/messages.ts:3224`, `:6844` |
| detach (modern) | `subscription.release.request` → `subscription.release.response` | JSON RPC | `packages/protocol/src/messages.ts:3402` |
| detach (legacy) | `unsubscribe_terminal_request` | JSON, no reply | `packages/protocol/src/messages.ts:3242` |
| live output | binary opcode `0x01 Output` | binary | `packages/protocol/src/binary-frames/terminal.ts:17` |
| legacy single-shot replay | binary opcode `0x05 Restore` | binary | `packages/protocol/src/binary-frames/terminal.ts:21` |
| chunked replay begin/data/end | binary opcodes `0x06`/`0x07`/`0x08` | binary | `packages/protocol/src/binary-frames/terminal.ts:22-24` |
| legacy JSON snapshot | binary opcode `0x04 Snapshot` | binary (dead code) | `packages/protocol/src/binary-frames/terminal.ts:20` |
| send input | `terminal_input` (`message.type "input"`) | JSON, no reply | `packages/protocol/src/messages.ts:3264`, `:3248` |
| resize | `terminal_input` (`message.type "resize"`) or binary `0x03` | JSON / binary | `packages/protocol/src/messages.ts:3250-3257`, `packages/protocol/src/binary-frames/terminal.ts:19` |
| mouse | `terminal_input` (`message.type "mouse"`) | JSON, no reply | `packages/protocol/src/messages.ts:3258-3261` |
| kill terminal | `kill_terminal_request` → `kill_terminal_response` | JSON RPC | `packages/protocol/src/messages.ts:3270`, `:6862` |
| capture terminal | `capture_terminal_request` → `capture_terminal_response` | JSON RPC | `packages/protocol/src/messages.ts:3276`, `:6871` |
| activity snapshot | `terminals_changed` (`TerminalInfo.activity`) | JSON push | `packages/protocol/src/messages.ts:6815`, `:6763` |
| attention notification | `terminal_attention_required` | JSON push | `packages/protocol/src/messages.ts:6891` |
| stream end | `terminal_stream_exit` | JSON push | `packages/protocol/src/messages.ts:6881` |
| clear attention | `client_heartbeat` (`focusedTerminalId`) | JSON, no reply | `packages/protocol/src/messages.ts:3088` |
| list scripts | `workspace.script.list.request` → `workspace.script.list.response` | JSON RPC | `packages/protocol/src/messages.ts:3204`, `:4866` |
| start script | `workspace.script.start.request` → `workspace.script.start.response` | JSON RPC | `packages/protocol/src/messages.ts:3210`, `:4871` |
| start script (legacy) | `start_workspace_script_request` → `start_workspace_script_response` | JSON RPC | `packages/protocol/src/messages.ts:3197`, `:4846` |
| stop script | `workspace.script.stop.request` → `workspace.script.stop.response` | JSON RPC | `packages/protocol/src/messages.ts:3217`, `:4876` |
| script status push | `script_status_update` | JSON push (event stream) | `packages/protocol/src/messages.ts:4686`, `:3366` |

## 12. Gotchas worth copying into the iOS client brief

1. **JSON, not binary, for input.** The binary `Input`/`Resize` opcodes exist daemon-side but no first-party client sends them; `terminal_input` JSON is the only supported path for a new client — `packages/server/src/terminal/terminal-session-controller.ts:242-278`, `packages/client/src/daemon-client.ts:6887-6889`.
2. **Slot ≠ subscriptionId.** Binary frames are routed by the 1-byte slot while JSON pushes are routed by `subscriptionId`; the subscribe response carries both (success branch only) — `packages/protocol/src/messages.ts:6847-6853`.
3. **Chunked replay arrives as ANSI bytes, not `xterm` messages.** Never assemble the whole replay and write it at once; feed incrementally. If your client lacks `terminal_chunked_replay`, you get one big `Restore` frame instead — `docs/terminal-performance.md:22`, `docs/protocol-compatibility.md:61-66`.
4. **Replay chunk bytes are ≤ 64 KiB, but the replay allocation is not bounded** — the worker serializes the whole ANSI string before delivery — `docs/terminal-performance.md:23`, `packages/server/src/terminal/terminal-replay.ts:24`.
5. **`restore.scrollbackLines` silently clamps to 500** for non-chunked (older ANSI) hosts; chunked hosts pass it through — `packages/server/src/terminal/terminal-restore.ts:49-54`.
6. **`subscribe_terminal_request` is a claim opportunity for the PTY size** on legacy sources: `restore.size` is applied as a claim before the stream binds; modern sources ignore it for sizing — `packages/server/src/terminal/terminal-session-controller.ts:745-755`.
7. **A viewer that falls > 256 KiB behind with > 4 MiB queued is silently re-synced** with ≤ 500 rows + screen; its explicit demand is preserved for later restores — `docs/terminal-performance.md:30`, `packages/server/src/terminal/terminal-restore.ts:24-34`.
8. **`terminal_stream_exit` is not PTY death.** `payload.error` means observation failure; absence of `error` means the stream ended cleanly (kill, PTY exit, workspace torn down) — `packages/protocol/src/messages.ts:6886`, `packages/client/src/daemon-client.ts:6802-6807`.
9. **`Snapshot` frames (0x04) are dead on modern hosts.** Do not implement a `TerminalState` renderer for them; JSON snapshots "have no rendering runtime" — `docs/protocol-compatibility.md:65-66`.
10. **`terminal-restore-modes` is mandatory.** Terminals without it show the host-update message; do not attach — `docs/protocol-compatibility.md:67`, `app/terminal/runtime/terminal-restore-options.ts:14-16`.
11. **`features` flags are one socket's contract.** Never read sibling sockets' features/capabilities — `docs/architecture.md:333`.
12. **Heartbeat focus clears finished-attention.** The daemon needs `focusedTerminalId` on heartbeats or finished terminals stay green forever — `packages/protocol/src/messages.ts:3088-3097`, `docs/terminal-activity.md:83-86`.
13. **`client_heartbeat` and `ping` are different messages.** Liveness is app-level `ping`/`pong`; session RPC timeouts are operation failures, not socket health — `docs/architecture.md:279`.
14. **Scripts are terminals.** A script row's `terminalId` is a normal terminal: killing it stops the script, and `isScript` on the terminal row flags it — `packages/protocol/src/messages.ts:6757`, `packages/server/src/server/session.ts:1193-1197`.
15. **Script stop in the app never calls `workspace.script.stop.request`** — it kills the backing terminal. If you implement stop RPC-side, match CLI semantics (`paseo script stop` → `workspace.script.stop.request`) — `app/screens/workspace/scripts/use-workspace-script-actions.ts:118-132`, `docs/service-proxy.md:29-39`.
16. **Proxy URLs depend on daemon TCP port and optional `publicBaseUrl`.** With no bind port, `localProxyUrl` is null and plain `proxyUrl` may still be public — `packages/server/src/server/service-proxy.ts:181-201`, `docs/service-proxy.md:41-60`.
17. **Hostnames are case-normalized and labels are sanitized.** Service `dev.test` in project "my app" on `feature/auth` → `dev-test--feature-auth--my-app.localhost`; `main`/`master` branch segment is omitted — `packages/server/src/server/service-proxy.ts:104-147`, `docs/service-proxy.md:11-27`.
18. **Terminal opcodes 0x01-0x08 and chunk opcode 0x31 are not the file-transfer/plugin spaces**; a single `decodeBinaryFrame`-style dispatcher must route by opcode — `packages/protocol/src/binary-frames/demux.ts:13-52`.

## 13. Minimal set for a v1 client

Hello: `clientType: "mobile"`, fresh `clientId`, negotiated `protocolVersion`, `hello_rejection`, `owned_subscriptions`, `terminal_chunked_replay`, `binary_chunking_v1` (only if you can pace sends; otherwise leave inbound-only), `terminal_reflowable_snapshot` (optional).

1. Require `server_info.features["terminal-restore-modes"] === true`, else the host-update UI and stop. Optionally read `terminal-grapheme-widths`, `terminal-size-ownership`, `terminal-input-mode-replay` to configure the renderer and key encoder.
2. Open the workspace directory subscription: `subscribe_terminals_request { workspaceId }`; apply `terminals_changed` snapshots wholesale (includes `activity` and `isScript`). Fallback: poll `list_terminals_request { workspaceId }` on focus.
3. Create: `create_terminal_request { cwd, workspaceId, name?, command?, args? }`; use the returned `terminal.id`.
4. Attach: wait for SwiftTerm to report its measured grid, send `subscribe_terminal_request { terminalId, restore: { mode: "visible-snapshot", scrollbackLines: 200, size: { rows, cols } } }`.
5. On `subscribe_terminal_response`: store `slot`/`subscriptionId`; feed binary `Output` frames into SwiftTerm by slot; on `ReplayBegin` record `rows/cols/retainedHistoryLines` and reset replay state; on `ReplayData` write bytes into the running parser (incremental, not concatenated); on `ReplayEnd` end replay mode (re-enable generated replies; apply latest measured size before live bytes).
6. Send input: `terminal_input { terminalId, message: { type: "input", data } }`. Encode key-bar presses through a Kitty/Win32-aware encoder tracked from output; otherwise plain `\r`, `\t`, `\x03`.
7. Resize: after focus and only on real geometry change — `terminal_input { ..., message: { type: "resize", rows, cols, intent: "claim" | "update" } }`. Claim on focus/keyboard-inset appearance; update for later geometry changes from this connection.
8. Detach/teardown: `subscription.release.request { subscriptionId }` (or let disconnect do it). Never send `unsubscribe_terminal_request` from a modern client.
9. Kill: `kill_terminal_request { terminalId, requestId }`.
10. Capture: `capture_terminal_request { terminalId, requestId }` (e.g. for "copy scrollback").
11. Activity: read `TerminalInfo.activity` from `terminals_changed`; derive dot via the shared `deriveTerminalActivityStatusBucket` logic; include `focusedTerminalId` in heartbeats so finished attention clears.
12. Scripts: `workspace.script.list.request { workspaceId, requestId }` to render the scripts panel (row: `scriptName`, `type`, `lifecycle`, `port`, `localProxyUrl`, `publicProxyUrl`, `proxyUrl`, `health`, `exitCode`, `terminalId`); start via `workspace.script.start.request` (or legacy `start_workspace_script_request`); stop via `workspace.script.stop.request` or by killing the row's `terminalId`; keep rows fresh with `observeEvents(["script_status_update"])` or by folding `workspace.scripts` from workspace descriptor refreshes. Show service URLs from `proxyUrl` (prefer `localProxyUrl`/`publicProxyUrl` when both exist).
13. Handle `terminal_stream_exit` by tearing down the view; treat `payload.error` as "re-attach", its absence as "closed".

Out of scope for v1: file-transfer/diff/plugin binary frames (`0x20`-`0x2f`, `0x40`-`0x4f`), `binary_chunking_v1` sends on React Native-style transports, `Snapshot` (0x04) rendering.

## 14. Document history

- 2026-11-08 — initial research pass. Every path:line citation below was re-opened and checked against `/home/paseo/dev/paseo-reference` on the same day.
Verified: 408 citation mentions (327 unique path:line locations) re-opened and checked against the checkout at /home/paseo/dev/paseo-reference; 47 corrected.
