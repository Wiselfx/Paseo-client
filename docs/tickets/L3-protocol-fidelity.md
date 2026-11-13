# L3 — Protocol fidelity: capabilities, create idempotency, readable connection errors, terminal focus

Read `_L-common.md` first. Branch: `l3-protocol`. Commit messages start with `L3:`.
Findings: `/home/paseo/dev/docs-audit/findings/` — `LEDGER.md` D-024, D-014, D-022, D-036, D-007;
`LEDGER-EXTRA.md` X-006; `REVIEW.md` (D-024's numbers were corrected there: upstream defines **22**
client capabilities).

## You own (Linux-compilable Core only)
`Packages/PaseoCore/Sources/PaseoProtocol/Handshake.swift`, `AgentControl.swift` (only `CreateAgentRequest`),
`Packages/PaseoCore/Sources/PaseoKit/DaemonClient.swift` (only `ConnectionError`),
`Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift` (only the presence/heartbeat part),
`Packages/PaseoCore/Sources/PaseoStore/DraftSession.swift` (only where it builds `CreateAgentRequest`),
new files, and new test files under `Packages/PaseoCore/Tests/`. Do NOT touch `HostSession.swift`,
`DaemonConnection.swift` or anything in `Packages/PaseoUI` or `App/`.

## Part A — hello capabilities (the daemon degrades its protocol for clients that do not advertise)
Upstream list: `/home/paseo/dev/paseo-upstream-ref/packages/protocol/src/client-capabilities.ts`
(`CLIENT_CAPS`, 22 names). Ours: `Handshake.swift` lines ~20-55 (`implemented`), currently advertising
`hello_rejection`, `terminal_chunked_replay`, `provider_subagents`, `projected_subagent_timeline`, and
(conditionally) `owned_subscriptions`, `workspace_setup_observation`, `voice`.
**Rule: advertise a capability only if our decoder handles what the daemon then sends.** For EACH of the
22 names do these four steps and record them in a table in your final message AND as a comment block
above `implemented`:
1. `grep -rn "<camelCaseName>\|<wire_name>" /home/paseo/dev/paseo-upstream-ref/packages/server/src /home/paseo/dev/paseo-upstream-ref/packages/protocol/src --include=*.ts | grep -v test` — find what the daemon changes when the capability is present (the `COMPAT(...)` comments in `client-capabilities.ts` already say).
2. Decide what that change means for us: does the daemon then send a new/extra message, field or enum
   value? Find our decoder for it (search our `Packages/PaseoCore/Sources/PaseoProtocol` with the wire name
   in snake_case AND camelCase).
3. If our decoder handles it (or the daemon only *stops downgrading* data we already decode as open
   strings/`.unknown` cases): **advertise it**. Likely yes: `all_providers` (we decode provider ids as
   strings), `explicit_event_subscriptions`, `custom_mode_icons`, `reasoning_merge_enum`,
   `timeline_replacement_invalidation` (we handle `agent.timeline.replacement`), `project_updates`,
   `workspace_setup_blocked`, `timeline_notifications`, `plugin_timeline_items`, `selective_agent_timeline`
   (the reviewer found it is gated on `owned_subscriptions`, which we send). Verify each before you add it.
4. If not handled (e.g. `binary_chunking_v1` — we never send chunked; `browser_host`;
   `plugin_binary_payloads`; `terminal_reflowable_snapshot`; `compact_provider_snapshots`;
   `provider_snapshot_references`; `background_agents`) **do not advertise**; write one line why.
Implementation: keep `implemented` as the single source of truth; the Swift names stay camelCase constants,
the wire strings exactly upstream's. Add a test `HandshakeCapabilitiesTests.swift` that (a) pins the exact
set of advertised wire names, (b) asserts every name is one of the 22 upstream names (copy the 22 strings
into the test as the allow-list), (c) asserts the JSON of `Hello` contains them.

## Part B — create_agent idempotency
Upstream: `packages/protocol/src/messages.ts` ~line 1862 `CreateAgentRequestMessageSchema` has
`idempotencyKey` (1–512 chars) and `clientMessageId`; SDK use: `packages/client/src/creation/index.ts`
(read how the key is generated and reused on retry).
1. `CreateAgentRequest` (our `AgentControl.swift:90`): add optional `idempotencyKey: String?` and
   `clientMessageId: String?`; encode them under exactly those wire keys, omitting when nil (look at how
   the existing optional fields encode; the struct is `PaseoRequest`).
2. `DraftSession.create`: generate one `idempotencyKey` (UUID string) and one `clientMessageId` **per
   user action**, store them on the draft/attempt so that a retry of the same action reuses the same
   values, and a new user action makes new ones. Read how `WorkspaceDirectory.swift:170-199` already does
   `idempotencyKey ?? UUID().uuidString` — reuse that pattern but keep the key stable across retries.
3. Tests: encode/decode round-trip; omitted when nil; same key on retry of one attempt, different key for
   a new attempt.

## Part C — connection errors a person can read
`DaemonClient.swift:82` `enum ConnectionError`. Upstream (reference.md in `public-docs/sdk/`): a request
whose response is lost is a *connection lost, outcome unknown* error; a mutation must be inspected before
retrying. 1. Add a computed property `public var outcomeUnknown: Bool` (true for `.disconnected`,
`.timeout`, `.closed`, `.transport`; false for `.rejected`, `.protocolViolation`). 2. Make the enum conform
to `LocalizedError` with a plain English sentence per case (no raw case names). Search
`/home/paseo/dev/Paseo-client/App/Sources/AppModel.swift` for `describe(` — it already has sentences for
connection errors; reuse their wording (copy the strings into the Core conformance; do not edit AppModel).
For `.rejected(reason:)` map `password_required` / `incorrect_password` to the words AppModel uses.
3. Tests: every case yields a non-empty `errorDescription` that does not contain the raw case name.

## Part D — heartbeat carries the focused terminal
`ClientHeartbeat` already has `focusedTerminalId` (`HostSettings.swift:339-380`, upstream
`messages.ts:3169`). The sender `HostSettingsStore.swift` `sendHeartbeat()` (~line 521) never fills it.
Add `focusedTerminalId: String?` state to the presence store next to `focusedAgentId` (copy exactly how
`focusedAgentId` is set, cleared, and triggers an immediate heartbeat when it changes) and pass it in
`sendHeartbeat()`. Upstream rule: when a terminal is focused, `focusedAgentId` is nil and vice versa
(read how upstream sets them: `grep -rn "focusedTerminalId" /home/paseo/dev/paseo-upstream-ref/packages/app/src`).
Tests in a new file next to the existing presence tests (find them: `grep -rln "ClientHeartbeat\|focusedAgentId" Packages/PaseoCore/Tests`).
List under "Found, not fixed": the terminal screen that must call the new setter (`WorkspaceTerminalsView.swift`).

## Proof
`swift build --build-tests` has no errors/warnings in your files; `swift test` passes — paste the totals.
Then, if the daemon is up (`paseo daemon status` shows it running on 127.0.0.1:6767), run once:
`cd Packages/PaseoCore && swift run paseo-probe --help` and use whichever probe subcommand lists agents or
connects, to prove the daemon still accepts our new hello (it must not close the connection). Paste the
command and the first lines of output. Never create or prompt agents with the probe.
