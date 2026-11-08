# 04 — Protocol: agents, permissions & settings

**Audit:** re-checked the agent/permission/settings wire facts against `packages/protocol/src/messages.ts`, `paseo-config-schema.ts`, `agent-profile.ts`, `schedule/*`, `operation-permissions.ts` and `packages/client/src`: message type strings, payload field names/optionality, enum values, `close_items` shape, config patch surface, revision types, plus the §15 v1 set. 196 facts checked, 24 corrected (chief fixes: `close_items_response` shape, `AgentListItemPayload` is *not* "snapshot minus three fields", the config patch cannot set most top-level keys and never requires `mcp.injectIntoAgents`, `expectedRevision` is `{mtimeMs, size}` not a string, `set_voice_mode_response.agentId` is required-nullable, and `cancel_agent_request` was missing from the v1 set).

Wire reference for a native iOS client that speaks the Paseo WebSocket protocol directly —
everything about agents except reading the timeline (covered separately). All `path:line`
citations point into the reference repo root `/home/paseo/dev/paseo-reference`. Bare
`messages.ts:NNNN` means `packages/protocol/src/messages.ts:NNNN`. Bare `app/…` means
`packages/app/src/…`. Schemas cited are zod declarations; the wire format is the JSON they
validate.

Transport recap (full treatment is the timeline doc's job):

- Top-level frames: `hello`, `recording_state`, `ping`/`pong`, `session` (`messages.ts:8037`–`8057`).
  Modern clients wrap every RPC in `{type:"session", message:{...}}` (`messages.ts:8020`, `8025`).
- `hello` advertises `clientType`, `protocolVersion`, `appVersion?` and `capabilities`
  (`messages.ts:7973`–`8011`). Capability bits live in
  `packages/protocol/src/client-capabilities.ts:1`. The TS SDK advertises everything except
  `browserHost` by default (`packages/client/src/connection/index.ts:127`).
- After `hello`, the daemon emits one `status` message with `payload.status === "server_info"`
  (`messages.ts:3796`, `4041`). It carries `serverId`, `version`, `protocolVersion?`,
  `permissions?` (daemon-granted semantic permissions, `messages.ts:3806`) and
  `features` (`messages.ts:3811`). Feature flags are the capability gates for the agent RPCs
  below. Every flag inside `features` is itself optional — a missing flag means "old host".
- Session RPCs correlate by `requestId`; failures arrive as `rpc_error`
  (`messages.ts:4060`, inbound union at `messages.ts:3412`, outbound union at
  `messages.ts:7253`). New RPCs use dotted names (`checkout.forge.set_auto_merge.request`);
  most agent RPCs predate that convention and stay flat — see `docs/rpc-namespacing.md:3`.
- The daemon authorizes every message type against semantic permissions
  (`packages/server/src/server/authorization/operation-permissions.ts:8` for inbound, `:238`
  for outbound); RPC name is not authority (`docs/permissions.md:3`). `workspace.read`/
  `workspace.write` cover agents; `daemon.manage` covers config; `automation.manage` covers
  schedules; `hub.execute` is accepted alongside `workspace.*` for Hub-driven sessions.
- Compatibility rules — append-only fields, no optional→required flips, new enum values gated
  on capabilities — are in `docs/protocol-compatibility.md:15`–`20`.

## 1. Creating an agent

There are two creation paths on the wire. The client SDK picks between them by
`server_info.features.agentRequestReceipts` / `creationLifecycle`; the choice is made once at
the client boundary (`packages/client/src/creation/index.ts:56`, capability read at
`packages/client/src/daemon-client.ts:3391`–`3394`).

### 1.1 `create_agent_request` — the established request/response path

**Purpose.** Create one agent, optionally with an initial prompt, attachments, images, labels,
and placement into an existing workspace. Still what the SDK falls back to against older
daemons.

**Request** — `create_agent_request` `messages.ts:1819`:

| field | type | req? | notes |
|---|---|---|---|
| `type` | literal `"create_agent_request"` | yes | |
| `idempotencyKey` | string (1–512) | optional | keyed creation; the daemon's creation journal joins/replays by it (`messages.ts:1820`) |
| `config` | `AgentSessionConfigSchema` (`messages.ts:505`) | yes | `provider` (string), `cwd` (string), `modeId?`, `model?`, `thinkingOptionId?`, `featureValues?` (record), `title?` (nullable, trimmed, ≤ MAX_EXPLICIT_AGENT_TITLE_CHARS), `providerOptions?`, `toolPolicy?`, `systemPrompt?`, `mcpServers?` (record of stdio/http/sse) |
| `env` | record<string,string> | optional | explicit env overrides, persisted with the agent (`docs/agent-lifecycle.md:25`) |
| `workspaceId` | string | optional | placement; omit to use the caller's workspace |
| `callerAgentId` | string | optional | agent-scoped creation; stamps `paseo.parent-agent-id` (`docs/agent-lifecycle.md:122`) |
| `worktreeName` | string | optional | **rejected** — legacy placement, see gotchas |
| `initialPrompt` | string | optional | |
| `clientMessageId` | string | optional | echoed as `messageId` on the canonical timeline row |
| `outputSchema` | record<string,unknown> | optional | structured output for Hub/automation |
| `images` | `ImageAttachmentSchema[]` (`messages.ts:1287`) | optional | `{data: base64, mimeType}` |
| `attachments` | `AgentAttachmentsSchema` (`messages.ts:1278`) | optional | normalized, unknown kinds dropped |
| `git` | `GitSetupOptionsSchema` (`messages.ts:1784`) | optional | **rejected** — legacy, see gotchas |
| `worktree` | `CreateAgentWorktreeTargetSchema` (`messages.ts:1801`) | optional | `{mode:"branch-off", newBranch, base?}` \| `{mode:"checkout-branch", branch}` \| `{mode:"checkout-pr", prNumber}` |
| `autoArchive` | boolean | optional | daemon archives after first terminal turn event (`docs/agent-lifecycle.md:244`) |
| `internal` | boolean | optional | retained for parse compat; public internal creation is rejected |
| `background` | boolean | optional | background agent — never raises attention, hidden from discovery/tabs/tracks (`docs/agent-lifecycle.md:200`) |
| `labels` | record<string,string> | defaults `{}` | |
| `requestId` | string | yes | correlation key |

**Response.** Legacy keyed sends correlate off the `status` message stream (no dedicated
response type):

- `status` / payload `AgentCreatedStatusPayloadSchema` `{status:"agent_created", agent: AgentSnapshotPayloadSchema, agentId, requestId}` — `messages.ts:4079`
- `status` / payload `AgentCreateFailedStatusPayloadSchema` `{status:"agent_create_failed", error, requestId, errorCode?}` — `messages.ts:4086`
- The SDK also reads `agent.create.response` when the daemon supports the modern path (see 1.2).

**Events it causes**

- `agent.create.update` (`messages.ts:5257`) — creation milestone snapshots (`CreationSnapshotSchema`, `messages.ts:5227`: `kind`, `idempotencyKey`, `revision`, `phase` ∈ `accepted|workspace_ready|agent_ready|prompt_started|completed|failed`, **`workspaceId: string|null` and `agentId: string|null` — present and nullable, not optional**, `workspace?`, `agent?`, `error: string|null`, `setupSkippedReason?`, `errorCode?`, `failedStage?`, `outcomeUnknown?`). Delivered only to the subscribed socket, and only with an explicit `creation.subscribe.request` (`messages.ts:1869`).
- `agent_update` upsert (`messages.ts:4381`) — once the agent is registered, all clients with list demand see it.
- `agent_stream` / `agent_status` for the first turn — timeline doc's territory.

**Capability gates.** No gate on the request itself; client-side the SDK selects legacy vs
modern by `features.agentRequestReceipts` (`messages.ts:3814`) and `features.creationLifecycle`
(`messages.ts:3817`). Background agents in inclusive reads need `background_agents`
(`messages.ts:3826`, `packages/server/src/server/session.ts:5797`); background workspaces need
`features.backgroundWorkspaces` (`messages.ts:3824`). Per-connection delivery varies by
`features.ownedSubscriptions` (`messages.ts:4000`) and `features.explicitEventSubscriptions`
(`messages.ts:3999`).

**Permissions.** `create_agent_request`: `["workspace.write","hub.execute"]`; inbound
`agent.create.request`: same (`operation-permissions.ts:76`, `:77`). Outbound
`agent.create.response` and `agent.create.update`: `["workspace.write","hub.execute"]`
(`operation-permissions.ts:248`–`:249`), `creation.subscribe.response`: `workspace.read` (`:251`).

**How the app uses it.** Draft tabs and new-workspace creation: `app/composer/draft/create-agent-request.ts:25`
(`client.createAgent`), `app/composer/draft/workspace-tab.tsx:174`, workspace+initial-agent
creation `app/screens/new-workspace-screen.tsx:309`. Builds `AgentSessionConfig` from the
composer (provider/model/mode/thinking/features) at `app/composer/draft/workspace-tab.tsx:153`.

**Gotchas**

- Placement never changes parentage; omitting `workspaceId` uses the caller's workspace, explicit
  `workspaceId` re-homes the agent without changing who it belongs to (`docs/agent-lifecycle.md:122`).
  `worktreeName` and `git` are rejected — placement goes through `createWorkspace`
  (`packages/client/src/daemon-client.ts:3455`); legacy git/worktree inputs
  fail with workspace-creation guidance (`docs/agent-lifecycle.md:147`).
- Creation is daemon-owned across socket lifetimes; the creation journal owns identity and
  execution for both legacy and modern RPCs, reconnect subscribes to the same
  `idempotencyKey` (`docs/architecture.md:344`–`:376`). Agent registration commits creation — a
  rejected first prompt is a turn error on the agent, not a failed create; reporting creation
  failure leaves an orphan (`docs/architecture.md:361`).
- `autoArchive` archives after the first terminal turn event (`turn_completed`/`turn_failed`/
  `turn_canceled`); an owned isolated workspace is archived too and its worktree is removed when
  the final workspace reference is gone (`docs/agent-lifecycle.md:244`).
- Background: `background: true` agents never raise attention and the workspace they create
  inherits the flag; caller-agent-scoped creation omits `background` and inherits the caller's;
  explicit true/false wins (`docs/agent-lifecycle.md:207`). Sources without the
  `background_agents` hello capability see only background *workspaces* (`docs/agent-lifecycle.md:217`).
- `notifyOnFinish` defaults to true for agent-scoped creation; set false for explicit-reporting
  children (`docs/agent-lifecycle.md:151`).
- The config schema is reused for `resume_agent_request` overrides; do not put creation-only
  semantics in `AgentSessionConfig` expecting them to apply later.

### 1.2 `agent.create.request` — modern receipt path

**Purpose.** Same inputs as 1.1, plus caller-selected resource IDs and delivery receipts. The
SDK uses this whenever the host advertises the receipt capabilities.

**Request** — `AgentCreateRequestSchema`, extends 1.1 with `type:"agent.create.request"`
(`messages.ts:1851`):

- `agentId` — uuid, optional. Supplied IDs retain identity on replay.
- `attachments` — `AgentAttachmentSchema[]` (strict per-item; unlike the legacy path it is not
  lenient-normalized).
- `subscribe` — boolean, optional; when true the daemon pushes `agent.create.update` milestones
  to the requesting socket.

**Response** — `agent.create.response` (`AgentCreateResponseSchema`, `messages.ts:5269`):

`payload {requestId, agent: AgentSnapshotPayloadSchema|null, error: string|null, creation?: CreationSnapshotSchema}`

**Events it causes.** `agent.create.update` (`messages.ts:5257`) on the requesting source when
`subscribe`/journal subscription is active; `creation.subscribe.request|response`
(`messages.ts:1869`, `:5260`) is the reconnect path — payload `{requestId, subscriptionId?,
snapshot: CreationSnapshotSchema|null, error}`. `agent_update` as in 1.1.

**Capability gates.** Client selects this path only if
`features.agentRequestReceipts`/`features.creationLifecycle` (`messages.ts:3814`, `:3817`) or, for
workspaces, `workspaceRequestReceipts` (`messages.ts:3816`). Legacy `create_agent_request` is
preserved for older hosts — no fallback fan-out beyond the client package
(`docs/protocol-compatibility.md:41`). Per protocol rules both shapes must remain parseable by
both peers (`docs/protocol-compatibility.md:18`–`:20`).

**Permissions.** Same inbound classification as 1.1 (`operation-permissions.ts:77`).

**How the app uses it.** Transparently through `client.createAgent` → `CreationClient.createAgent`
(`packages/client/src/creation/index.ts:56`); the app passes `idempotencyKey` for draft tabs
(`app/composer/draft/workspace-tab.tsx:174`). Direct callers can pass `subscribe` and receive
`agent.create.update` via the creation observation API
(`packages/client/src/creation/index.ts:24`).

**Gotchas.** The creation journal, not the request, owns idempotency: retries join the in-flight
operation or reuse committed stages; explicit IDs/receipts against a host without the capability
produce "update the host" errors rather than silent degradation
(`packages/client/src/creation/index.ts:64` and `:98`, `docs/architecture.md:352`). An interrupted
side effect with no conclusive receipt yields `outcomeUnknown` in the snapshot — never resend the
prompt automatically (`docs/architecture.md:358`).

### 1.3 `WorkspaceInitialAgentSchema` — workspace + agent in one request

**Purpose.** The shape of the `agent` member when `workspace.create.request` creates its initial
agent (`packages/protocol/src/messages.ts:1858`). Same fields as `AgentCreateRequestSchema`
minus `type`, `requestId`, `idempotencyKey`, `subscribe`, `workspaceId`, `worktree`,
`worktreeName`, `git`. Placement is implied by the workspace creation; the agent must not carry a
`cwd` outside it (`docs/agent-lifecycle.md:147`). See the worktree doc for the workspace side.

### 1.4 Events after registration

`agent_update` (upsert/remove, `messages.ts:4381`) is the normal liveness signal; snapshots carry
`status`, `requiresAttention`/`attentionReason`/`attentionTimestamp`, `pendingPermissions`,
`labels`, `background` (`messages.ts:881`–`:918`). `agent_status` (`messages.ts:4415`) duplicates
the latest snapshot for legacy polling; `agent_list` (`messages.ts:4424`) is the legacy full-list
push. Removals are announced as `agent_deleted` (`messages.ts:5546`) / `agent_archived`
(`messages.ts:5554`), each correlated by `requestId` when triggered by an RPC.

## 2. Sending a message to an agent

### 2.1 `send_agent_message_request`

**Purpose.** Deliver a user (or agent-originated) message to an existing agent, replacing or
steering the running turn. This is the composer's submit RPC.

**Request** — `SendAgentMessageRequestSchema` `messages.ts:1460`:

| field | type | req? | notes |
|---|---|---|---|
| `type` | literal `"send_agent_message_request"` | yes | |
| `requestId` | string | yes | |
| `agentId` | string | yes | full ID, unique prefix, or exact title; server resolves |
| `text` | string | yes | |
| `sourceAgentId` | string (min 1) | optional | agent-originated prompts; opaque sender identity (`docs/agent-lifecycle.md:153`) |
| `sourceAgentServerId` | string (min 1) | optional | qualified address; gated client-side on `features.agentMessageBatching` (`packages/client/src/daemon-client.ts:4153`) |
| `sessionMode` | string | optional | conflicting session-mode choices are delivered in order (`docs/agent-lifecycle.md:153`) |
| `messageId` | string | optional | client-provided dedup id; canonical for the timeline row |
| `activeTurnBehavior` | `"interrupt"\|"steer"` | optional | `ActiveTurnBehaviorSchema` `messages.ts:1292`; default is interrupt-and-replace |
| `images` | `ImageAttachmentSchema[]` | optional | base64 |
| `attachments` | `AgentAttachmentsSchema` | optional | lenient-normalized, unknown kinds dropped (`messages.ts:1265`–`:1276`) |

Note: `sourceAgentId` is gated client-side on `features.agentMessageProvenance` and
`sourceAgentServerId` on `features.agentMessageBatching` — sending them to an old host throws
before anything reaches the wire (`packages/client/src/daemon-client.ts:4148`–`:4154`).

**Response** — `send_agent_message_response` (`SendAgentMessageResponseMessageSchema`,
`messages.ts:5323`):

`payload {requestId, agentId, accepted: boolean, deliveryStatus?: "queued", error: string|null}`

**Events it causes.** A queued delivery acknowledges admission before provider dispatch
(`deliveryStatus:"queued"`) — the parent can finish in the same quiet window; human prompts
dispatch directly. The turn itself streams as `agent_stream` events (timeline doc), and
`agent_status`/`agent_update` carry the resulting state change.

**Capability gates.** Client-side: `features.agentMessageProvenance`, `features.agentMessageBatching`
(`messages.ts:4007`–`:4008`). Session-mode ordering is always on. No daemon-side gate.

**Permissions.** `send_agent_message_request`: `["workspace.write","hub.execute"]`
(`operation-permissions.ts:184`); `send_agent_message_response`: `["workspace.write","hub.execute"]`
(`operation-permissions.ts:433`).

**How the app uses it.** `app/composer/actions.ts:222` (`dispatchComposerAgentMessage`, sends
`messageId` clientMessageId); `app/composer/index.tsx` feeds the submit path. Client SDK:
`packages/client/src/daemon-client.ts:4142` (`sendAgentMessage`), convenience alias
`sendMessage` (`:4194`). CLI `paseo send` uses the same RPC.

**Gotchas**

- Two schemas exist for this: `SendAgentMessageSchema` (`type:"send_agent_message"`,
  `messages.ts:1295`) is **not** in either session union and nothing references it — do not
  implement it. Only `send_agent_message_request` is on the wire.
- `activeTurnBehavior:"steer"` is best-effort admission against the exact foreground turn; a
  provider that cannot steer reports `unavailable` and the SDK falls back to
  interrupt-and-replace. An adapter *error* leaves the steer's fate ambiguous — no retry, no
  interrupt (`docs/providers.md:106`). Slash-command inputs report `unavailable` on Pi.
- Queued delivery is in-memory; a crash can lose queued prompts, and the durable receipt stays
  pending until dispatch ack — it never becomes completed by accident
  (`docs/agent-lifecycle.md:155`).
- Timeline row dedup keys off `clientMessageId == messageId`; the manager records the canonical
  row at `startTurn` acceptance (`docs/providers.md:104`).

## 3. Changing a running agent's mode, model, thinking, features

All five RPCs share one payload shape, `AgentActionResponsePayloadSchema`
(`messages.ts:2069`): `payload {requestId, agentId, accepted: boolean, error: string|null,
notice?: AgentProviderNotice|null}` where the notice is `{type:"info"|"warning"|"error",
message}` (`messages.ts:332`, `:2069`). Providers return a notice when a change is staged for the
next turn or needs user context; the app renders it as a toast (`docs/providers.md:512`).

### 3.1 `set_agent_mode_request`

**Request** — `messages.ts:2062`: `{type, agentId, modeId: string, requestId}`. Mode IDs can be
full URIs for ACP providers (`copilot`) — never assume short slugs; the manifest `defaultModeId`
must match exactly (`docs/providers.md:558`).
**Response** — `set_agent_mode_response` (`SetAgentModeResponseMessageSchema`,
`messages.ts:2077`): the shared action payload.
**Events it causes.** `agent_update` upsert with new `currentModeId` once the provider applies it.
**Capability gates.** None for mode itself; icons are downgraded for old clients via
`CLIENT_CAPS.customModeIcons` (`packages/protocol/src/client-capabilities.ts:20`, daemon-side
`packages/server/src/server/session.ts:1068`).
**Permissions.** `set_agent_mode_request` / `set_agent_mode_response`: `workspace.write`
(`operation-permissions.ts:186`, `:435`).
**How the app uses it.** `app/composer/agent-controls/mode-control.tsx:285`; also
`app/contexts/session-context.tsx:758`.
**Gotchas.** ACP mode IDs are URIs (`docs/providers.md:558`); modes are discovered dynamically —
runtime values beat the static manifest (`docs/providers.md:560`).

### 3.2 `set_agent_model_request`

**Request** — `messages.ts:2082`: `{type, agentId, modelId: string|null, requestId}`. `null`
clears the override (provider default).
**Response** — `set_agent_model_response` (`messages.ts:2089`), shared action payload.
**Events.** `agent_update` with `model` set; effective thinking may change with the model
(`effectiveThinkingOptionId` on `AgentSnapshotPayloadSchema`, `messages.ts:881`).
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:187`, `:436`).
**How the app uses it.** `app/composer/agent-controls/index.tsx:1664`; persisted as a
per-workspace draft preference (`app/composer/agent-controls/index.tsx:1666`).
**Gotchas.** Saved provider/model choices are user intent — a catalogue failure must not erase
them or substitute another model (`docs/providers.md:159`).

### 3.3 `set_agent_thinking_request`

**Request** — `messages.ts:2094`: `{type, agentId, thinkingOptionId: string|null, requestId}`.
**Response** — `set_agent_thinking_response` (`messages.ts:2101`), shared action payload.
**Events.** `agent_update` with `thinkingOptionId`/`effectiveThinkingOptionId`.
**Capability gates.** `features.agentThinkingUpdate` advertises that the daemon accepts this RPC
(`messages.ts:3939`); added v0.2.4, gate removal after 2027-01-28.
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:188`, `:437`).
**How the app uses it.** `app/composer/agent-controls/index.tsx:1726`; also
`app/contexts/session-context.tsx:782`.
**Gotchas.** Claude thinking options derive from the curated Claude manifest
(`docs/providers.md:62`); a model that does not support the requested effort is silently
downgraded — the hook-level level is the truth (`docs/agent-lifecycle.md:384`).

### 3.4 `set_agent_feature_request`

**Request** — `messages.ts:2106`: `{type, agentId, featureId: string, value: unknown, requestId}`.
Features are daemon/provider-computed `{type:"toggle", value: boolean, …}` or
`{type:"select", value: string|null, options:[…]}` (`messages.ts:338`–`:362`), listed on the
snapshot (`AgentSnapshotPayloadSchema.features`, `messages.ts:887`) and by
`list_provider_features_request` (§8.1).
**Response** — `set_agent_feature_response` (`messages.ts:2114`), shared action payload.
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:185`, `:434`).
**How the app uses it.** `app/composer/agent-controls/index.tsx:1754`.
**Gotchas.** Feature sets are provider- and model-specific; list them for the exact draft config
you hold, do not reuse across models (`docs/providers.md:118`).

### 3.5 `agent.config.apply.request` — bundle apply

**Request** — `messages.ts:2139`: `{type, agentId, config: AgentConfigApplySchema (messages.ts:2124),
requestId}` where config is `{modelId? (null clears), modeId?, thinkingOptionId? (null clears),
featureValues?}` — all omitted fields are left alone. One request prevents client interruption
and other mutations interleaving between bundle steps; provider-level rejection can still leave
earlier steps applied (`messages.ts:2134`–`:2137`).
**Response** — `agent.config.apply.response` (`AgentConfigApplyResponseMessageSchema`,
`messages.ts:2146`), shared action payload.
**Events.** One `agent_update` after the bundle settles.
**Capability gates.** `features.agentConfigApply` (`messages.ts:4030`); `features.agentProfiles`
(`messages.ts:4028`) gates the profile UI that is the main caller.
**Permissions.** `["workspace.write","hub.execute"]` both directions
(`operation-permissions.ts:19`, `:253`).
**How the app uses it.** Profile application reconciles a saved profile against the live
features and calls this: `app/agent-profiles/internal/use-agent-profile-picker.ts:153`. Gated in
the UI by `features.agentProfiles && features.agentConfigApply`
(`app/agent-profiles/internal/capabilities.ts:7`).
**Gotchas.** Agent profiles themselves are daemon-persisted config, not a separate RPC — see
§12.10. `systemPrompt` is deliberately not applicable to running agents; profiles carry no prompt
(`packages/protocol/src/agent-profile.ts:8`–`:12`).

## 4. Agent lifecycle: update, archive, delete, cancel, resume, detach

### 4.1 `update_agent_request` — rename and labels

**Request** — `messages.ts:1012`: `{type, agentId, name?: string, labels?:
record<string,string>, requestId}`. `name` renames; `labels` **merge** (send only the keys to
change). Daemon stores title as `title` on the snapshot.
**Response** — `update_agent_response` (`messages.ts:2182`): shared action payload.
**Events.** `agent_update` upsert carrying new `title`/`labels`.
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:210`, `:457`).
**How the app uses it.** Rename: `app/screens/workspace/use-workspace-tab-rename.tsx:76`. Open-tab
label bookkeeping for subagents: `app/subagents/use-open-agent-tab-labels.ts:67` and
`app/screens/workspace/workspace-screen.tsx:2008`, `:2309`.
**Gotchas.** Labels are the lifecycle mechanism for subagents: `paseo.parent-agent-id` marks the
parent, `paseo.open-agent-tab.<client-id>=true` protects an open tab; detach clears both
(`docs/agent-lifecycle.md:433`). The open-tab label is per client — re-registering it on
reconnect is correct, not noise.

### 4.2 `delete_agent_request` — hard delete

**Request** — `messages.ts:993`: `{type, agentId, requestId}`.
**Response.** No dedicated response; the daemon emits `agent_deleted` (`messages.ts:5546`) with
`payload {agentId, requestId}` — correlated by `requestId`.
**Events.** `agent_deleted`; also an `agent_update`/directory tombstone for list sync.
**Permissions.** `delete_agent_request` inbound `workspace.write` (`operation-permissions.ts:85`);
`agent_deleted` outbound `["workspace.read","hub.execute"]` (`operation-permissions.ts:278`).
**How the app uses it.** `app/contexts/session-context.tsx:712` (delete from agent menu).
**Gotchas.** Delete is distinct from archive (§4.3); deleting removes the agent record from the
store. Archive is the soft delete clients should prefer for user-facing "close" semantics
(`docs/agent-lifecycle.md:239`–`:244`).

### 4.3 `archive_agent_request` — soft delete

**Request** — `messages.ts:999`: `{type, agentId, requestId}`.
**Response.** None — daemon emits `agent_archived` (`messages.ts:5554`) with
`payload {agentId, archivedAt: string (ISO 8601), requestId}`.
**Events it causes.** `agent_archived`; cascades: daemon detaches cross-workspace/open-tab
children and archive-archives the rest, recursively (`docs/agent-lifecycle.md:252`). Auto-archive
also comes from `autoArchive` at creation (§1.1).
**Capability gates.** None on the request; `agent_archived` is a plain broadcast event.
**Permissions.** `archive_agent_request` `["workspace.write","hub.execute"]` inbound
(`operation-permissions.ts:40`); `agent_archived` outbound `["workspace.read","hub.execute"]`
(`operation-permissions.ts:276`).
**How the app uses it.** `app/hooks/use-archive-agent.ts:395` (mutation), tab-close policy
(root agents archive on close) in `app/screens/workspace/workspace-screen.tsx:2034` and
`app/components/agent-list.tsx:400`.
**Gotchas.** Archive is a **global** lifecycle gesture — every client reclassifies the agent;
closing a tab on a root agent archives it, closing a subagent tab is layout-only
(`docs/agent-lifecycle.md:321`). The `archivedAt` field is on the snapshot
(`messages.ts:909`) — persist it, don't infer from lists.

### 4.4 `cancel_agent_request` — stop the turn

**Request** — `messages.ts:1955`: `{type, agentId, requestId?}` (requestId optional!).
**Response** — `cancel_agent_response` (`CancelAgentResponseMessageSchema`, `messages.ts:5208`):
`payload {requestId, agentId, agent: AgentSnapshotPayloadSchema|null, error?: string|null}` —
`requestId` may be absent on the wire when none was sent.
**Events.** `agent_stream` terminal turn events (`turn_canceled`) and `agent_update`.
**Permissions.** `["workspace.write","hub.execute"]` inbound (`operation-permissions.ts:45`);
`cancel_agent_response` `["workspace.write","hub.execute"]` outbound (`operation-permissions.ts:290`).
**How the app uses it.** `app/contexts/session-context.tsx:699` (`_cancelAgentRun`);
`app/composer/actions.ts:178` (`cancelComposerAgent`).
**Gotchas.** Cancellation is idempotent at the provider boundary and scoped to the exact
foreground turn; a rejected/timed-out interrupt keeps the turn and blocks replacement
(`docs/agent-lifecycle.md:109`–`:117`). Stopping a Pi agent requires provider-native
`clear_queue`-then-`abort` ordering (`docs/providers.md:108`).

### 4.5 `resume_agent_request`, `import_agent_request`, `refresh_agent_request`

**Resume** — `messages.ts:1930`: `{type, handle: AgentPersistenceHandleSchema (messages.ts:858,
nullable-ok), overrides?: Partial<AgentSessionConfig>, requestId}`. Response: a `status` message
`agent_resumed` (`AgentResumedStatusPayloadSchema`, `messages.ts:4093`) with
`{status, agent, agentId, requestId, timelineSize?}`. Used by `ensureAgentLoaded`; a closed agent
reopens under the same Paseo ID (`docs/agent-lifecycle.md:41`).

**Import** — `messages.ts:1937`: `{type, provider?, providerId?, sessionId?, providerHandleId?,
cwd?, workspaceId?, labels?, requestId}`. Imports a provider-native session; the daemon resumes
it, hydrates history, and publishes the Paseo agent only once ready
(`docs/providers.md:120`).

**Refresh** — `messages.ts:1949`: `{type, agentId, requestId}`. Response `agent_refreshed`
(`messages.ts:4100`, `{status, agentId, requestId, timelineSize?}`); rebuilds runtime/history.

**Permissions.** All three inbound `workspace.write` (`operation-permissions.ts:174`, `:119`,
`:170`). Responses ride `status` (`workspace.read`/`hub.execute` outbound via the generic status
row) — resume/import return the agent in the status payload.
**How the app uses it.** The app rarely calls these directly; runtime residency is
daemon-managed (`docs/agent-lifecycle.md:17`). History import UI lives behind
`fetch_recent_provider_sessions_request` (out of scope here).
**Gotchas.** Resume from persisted records is best-effort after a crash; graceful shutdown
records intent first, and only agents recorded as `running` are resumed
(`docs/agent-lifecycle.md:17`–`:20`). Explicit creation env overrides are reapplied
(`docs/agent-lifecycle.md:25`).

### 4.6 `wait_for_finish_request` — bounded wait

**Request** — `messages.ts:1476`: `{type, requestId, agentId, timeoutMs?: int>0}`.
**Response** — `wait_for_finish_response` (`messages.ts:5334`):
`payload {requestId, status: "idle"|"error"|"permission"|"timeout", final: AgentSnapshotPayloadSchema|null, error: string|null, lastMessage: string|null}`.
**Events.** None; resolves on turn settlement or `timeoutMs` (client default 60 s budget on the
socket, but the operation itself has no default timeout server-side).
**Permissions.** `workspace.read` inbound and outbound (`operation-permissions.ts:213`,
`:460`).
**How the app uses it.** Not used by the app's UI directly; the client SDK exposes
`waitForFinish` (`packages/client/src/daemon-client.ts:6691`) for agent-to-agent and tests.
**Gotchas.** Returns `permission` if the agent parks on a permission request — check before
assuming completion (`docs/agent-lifecycle.md:183`).

### 4.7 `agent.detach.request` — leave the parent's track

**Request** — `messages.ts:2151`: `{type, agentId, requestId}`.
**Response** — `agent.detach.response` (`AgentDetachResponseMessageSchema`, `messages.ts:2157`),
shared action payload.
**Events.** `agent_update` upsert with cleared `paseo.parent-agent-id` /
`paseo.open-agent-tab.*` labels — every client reclassifies the agent to root
(`docs/agent-lifecycle.md:395`).
**Capability gates.** `features.agentDetach` (`messages.ts:3937`).
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:20`, `:254`).
**How the app uses it.** Detach button on subagent track rows (gated on
`features.agentDetach`): `app/panels/agent-tracks.tsx:68`.
**Gotchas.** Detach is a manual lifecycle gesture, not an MCP tool; it does not stop/archive/
move/restart the agent — only labels are cleared (`docs/agent-lifecycle.md:149`). Parent archive
detaches children that are in another workspace or have an open tab, instead of archiving them
(`docs/agent-lifecycle.md:127`).

### 4.8 `agent.rewind.request` — rewind conversation/files

**Request** — `messages.ts:2164`: `{type, agentId, messageId: string, mode:
"conversation"|"files"|"both", requestId}`.
**Response** — `agent.rewind.response` (`AgentRewindResponseMessageSchema`, `messages.ts:2172`):
`payload {requestId, agentId, ok: boolean, error: string|null}`.
**Events.** `agent_update`, timeline replacement items (`agent.timeline.replacement`).
**Capability gates.** `features.rewind` (`messages.ts:3911`) plus per-provider
`supportsRewindConversation/Files/Both` capability flags on the snapshot (`messages.ts:427`).
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:26`, `:262`).
**How the app uses it.** Rewind affordance in the chat (timeline doc).
**Gotchas.** Rewind resolves the wire `messageId` to the provider identity — a submitted prompt is
not rewindable until its provider echo lands (`docs/providers.md:112`).

### 4.9 `close_items_request` — batch close

**Request** — `messages.ts:1005`: `{type, agentIds: string[] (default []), terminalIds:
string[] (default []), requestId}`.
**Response** — `close_items_response` (`CloseItemsResponseSchema`, `messages.ts:5573`):
`payload {requestId, agents: [{agentId, archivedAt: string}], terminals: [{terminalId, success: boolean}]}` —
two typed arrays, **not** one `results` array, and no per-row `error` field. Treat every
`agents[]` row as archived (it carries `archivedAt` and nothing else) and check
`terminals[].success` per terminal.
**Permissions.** `workspace.manage` both directions (`operation-permissions.ts:75`, `:321`).
**How the app uses it.** Bulk tab close (`app/screens/workspace/workspace-screen.tsx:2300`-area —
clients that want server-acknowledged batch close use this instead of N `archive_agent_request`s).
This is the one agent-lifecycle RPC that is `workspace.manage`, not `write`.

## 5. Agent snapshots (shared payload)

`AgentSnapshotPayloadSchema` (`messages.ts:881`) is what creation responses, `fetch_agents`,
`fetch_agent`, `agent_update` upserts, `cancel_agent_response.final`, and
`wait_for_finish_response.final` all carry:

`{id, provider, cwd, workspaceId?, model: string|null, features?, thinkingOptionId?: string|null,
effectiveThinkingOptionId?: string|null, createdAt, updatedAt, lastUserMessageAt: string|null,
status: "initializing"|"idle"|"running"|"error"|"closed" (messages.ts:307), backgroundWork?:
{count}, activeTurn?: {turnId, startedAt: string|null}|null, capabilities (provider capability
flags, messages.ts:417), currentModeId: string|null, availableModes: AgentMode[]
(messages.ts:309), pendingPermissions: AgentPermissionRequestPayload[], persistence:
AgentPersistenceHandle|null, runtimeInfo?, lastUsage?, lastError?: string, title: string|null,
labels (default {}), requiresAttention?: boolean, attentionReason?:
"finished"|"error"|"permission"|null, attentionTimestamp?: string|null, archivedAt?: string|null,
providerUnavailable?: boolean, internal?: boolean, background?: boolean}`

`AgentListItemPayloadSchema` (`messages.ts:920`) is a **distinct reduced row**, not the snapshot
minus a few fields: `{id, shortId, title, provider, model, thinkingOptionId?,
effectiveThinkingOptionId?, status, backgroundWork?, cwd, createdAt, updatedAt,
lastUserMessageAt, archivedAt?, requiresAttention?, attentionReason?, attentionTimestamp?,
labels, providerUnavailable?}`. It has **no `workspaceId`, `features`, `capabilities`,
`currentModeId`, `availableModes`, `pendingPermissions`, `persistence`, `runtimeInfo`,
`lastUsage`, `lastError`, `internal` or `background`** — group sidebar rows by `cwd`, or fetch the
snapshot when you need `workspaceId`/feature state. List pushes arrive as
`agent_update` (upsert/remove, `messages.ts:4381`); the one-shot list response is
`fetch_agents_response` (`messages.ts:4463`) wrapping `{entries, pageInfo, requestId, …}`.
History is `fetch_agent_history_request`/`fetch_agent_history_response`
(`messages.ts:1420`, `:4474`); single-agent fetch is `fetch_agent_request` /
`fetch_agent_response` (`messages.ts:1453`, `:4916`) and also resolves unique ID prefixes and
exact titles (`messages.ts:1455`).

**How the app uses it.** Everything agent-shaped renders off these. `app/stores/session-store.ts`
keeps them; directory sync reconciliation in `docs/architecture.md:130`.

**Gotcha.** `labels` defaults to `{}` — never null. `status` lifecycle and normalization
(`running`/`initializing` are normalized away at archive time) is in `docs/agent-lifecycle.md:1`.

## 6. Agent permission requests and responses

The permission flow is the one place where the daemon blocks agent work on the client:
agent → daemon → client → user decision → daemon → agent.

### 6.1 `agent_permission_request` (daemon → client, event)

**Purpose.** One pending approval: tool call, plan acceptance, question, or mode switch.

**Event** — `AgentPermissionRequestMessageSchema` `messages.ts:5527`:

`payload {subscriptionId?: string, agentId: string, request: AgentPermissionRequestPayloadSchema}`

`AgentPermissionRequestPayloadSchema` (`messages.ts:544`):

| field | type | req? | notes |
|---|---|---|---|
| `id` | string | yes | request id; reused in `agent_permission_resolved` |
| `provider` | string | yes | |
| `name` | string | yes | tool/permission name |
| `kind` | `"tool"\|"plan"\|"question"\|"mode"\|"other"` | yes | |
| `title` | string | optional | |
| `description` | string | optional | |
| `input` | record<string,unknown> | optional | raw provider input |
| `detail` | `ToolCallDetailPayloadSchema` (`messages.ts:595`) | optional | normalized tool call (shell/read/edit/write/search/…) |
| `suggestions` | `AgentPermissionUpdateSchema[]` | optional | provider-suggested permission updates (`messages.ts:519`) |
| `actions` | `AgentPermissionActionSchema[]` | optional | offerable answers, `{id, label, behavior:"allow"|"deny", variant?, intent?: "implement"|"implement_resume"|"dismiss"}` (`messages.ts:520`) |
| `metadata` | record<string,unknown> | optional | provider-specific, e.g. `planText` for plan approvals |

**Capability gates.** None on the event; delivered to every session that subscribes to
`agent_permission_request` (§7.5) or legacy broadcast. ACP auto-accept does not resolve
single-choice chooser questions — they always wait for the user (`docs/providers.md:35`).
**Permissions.** Outbound `["workspace.read","hub.execute"]` (`operation-permissions.ts:279`).
**How the app uses it.** `app/contexts/session-context.tsx:523` stores it in the pending
permissions map; rendered by `app/agent-stream/view.tsx:154` (permission card) and
`app/components/question-form-card.tsx:35` (question form); the composer disables submit while
any permission is pending (`app/composer/index.tsx:1619`).

### 6.2 `agent_permission_resolved` (daemon → client, event)

**Event** — `messages.ts:5536`:

`payload {subscriptionId?: string, agentId: string, requestId: string, resolution:
AgentPermissionResponseSchema (messages.ts:528)}`

Fires when the provider emits `permission_resolved` (any source, not just the client that
answered — `packages/server/src/server/session.ts:2163`–`:2171` emits it for provider-originated
resolutions, e.g. auto-accept and timeouts), or when this session answers via
`agent_permission_response` (reply is source-owned for modern clients,
source-owned for modern clients (`packages/server/src/server/session.ts:5435`)).

**Permissions.** Outbound `["workspace.write","hub.execute"]` (`operation-permissions.ts:280`).
**How the app uses it.** `app/contexts/session-context.tsx:535` removes the pending card.

### 6.3 `agent_permission_response` (client → daemon, RPC)

**Request** — `messages.ts:2318`:

`{type:"agent_permission_response", agentId: string, requestId: string, response:
AgentPermissionResponseSchema}`

`AgentPermissionResponseSchema` (`messages.ts:528`) is a discriminated union on `behavior`:

- `behavior:"allow"` + `selectedActionId?: string` + `updatedInput?: record<string,unknown>` +
  `updatedPermissions?: AgentPermissionUpdateSchema[]` — the client may pick a provider action
  (`selectedActionId`), edit the tool input, or attach permission updates.
- `behavior:"deny"` + `selectedActionId?` + `message?: string` + `interrupt?: boolean` — deny
  optionally interrupts the turn.

**Response.** None directly. Outcomes: `agent_permission_resolved` to *every* observing source
(provider-emitted path) and/or source-owned delivery for the answering session; the requesting
client should correlate on `agent_permission_resolved.payload.requestId`. The SDK wraps the wait:
`respondToPermissionAndWait` resolves on that event (`packages/client/src/daemon-client.ts:6550`).
**Events it causes.** Provider may resume the turn → `agent_stream` rows; `agent_update`;
if the child agent was a watched subagent, the finish/permission notification fires again after
this response (`docs/agent-lifecycle.md:183`).
**Permissions.** `workspace.write` inbound (`operation-permissions.ts:39`); outbound resolved is
`["workspace.write","hub.execute"]` (`operation-permissions.ts:280`).
**How the app uses it.** `app/agent-stream/view.tsx:1561` (`respondToPermissionAndWait`, 15 s
timeout); one-shot `respondToPermission` at `app/contexts/session-context.tsx:799`. Deny is sent
with `message:"Denied by user"` / `selectedActionId` when a card action is tapped
(`app/agent-stream/view.tsx:1606`).

### 6.4 Pending permissions in snapshots

`AgentSnapshotPayloadSchema.pendingPermissions` carries the full array at snapshot time
(`messages.ts:899`), so a reconnecting client rebuilds the pending set without an event backlog.
`AgentListItemPayloadSchema` does **not** carry them (`messages.ts:920`) — you need the snapshot
(`fetch_agent_request`, `messages.ts:1453`) or the live event.

**Gotchas.**

- The event and the snapshot can disagree transiently; the app keys pending cards by
  `agentId:request.id` derived keys (`app/contexts/session-context.tsx:529`–`:531`).
- `kind === "question"` means the provider is waiting on structured user input
  (Pi `ask_user` surfaces as question permissions); render it as a form, not a tool approval
  (`docs/providers.md:90`).
- Deny with `interrupt: true` cancels the provider turn; deny without it lets the provider
  settle on its own. Providers bridge native approval dialogs differently — OMP approval
  dialogs (`docs/providers.md:67`), Pi `extension_ui_request` (`docs/providers.md:90`), ACP
  `session/request_permission`.
- `suggestions` are provider hints for `updatedPermissions`; applying them blindly can widen
  authority — the daemon does not re-check them against `docs/permissions.md`.
- The notification copy for permission reasons includes the request payload so a watching parent
  can respond without a fetch (`docs/agent-lifecycle.md:183`).
- Semantic permissions are daemon-wide: `workspace.write` authorizes `agent_permission_response`
  regardless of which agent — there is no per-agent grant today (`docs/permissions.md:30`).

## 7. Attention, notifications and push

### 7.1 `agent_attention_required` (daemon → client, event)

**Purpose.** The agent finished, errored, or needs a permission — one signal per transition.

**Event** — `AgentAttentionRequiredMessageSchema` `messages.ts:5172`:

`payload {subscriptionId?: string, agentId: string, reason:
"finished"|"error"|"permission", timestamp: string (ISO), shouldNotify: boolean,
notification?: {title: string, body: string, data: {serverId: string, workspaceId?: string,
agentId: string, reason: "finished"|"error"|"permission"}}}`

**Events it causes.** None beyond delivery. It is forwarded from the timeline `attention_required`
stream event (`packages/server/src/server/session.ts:1437`–`:1443`) and re-planned per client by
the presence policy (`packages/server/src/server/agent-attention-policy.ts:1`): a client focused
on the agent (present ≤ 180 s, app visible, same `focusedAgentId`) suppresses the notification
entirely; the most recently present client otherwise receives the in-app copy; push is sent only
when no client is present *and* the reason is push-eligible (everything except `error`)
(`packages/server/src/server/agent-attention-policy.ts:3`, `:78`).

**Capability gates.** Modern clients opt into event delivery per-event via
`session.events.set_subscription` (`messages.ts:3380`) with `notifications: true` to receive
`shouldNotify: true` (`packages/server/src/server/session.ts:9031`–`:9049`); legacy clients rely
implicitly on `explicitEventSubscriptions` semantics (`packages/server/src/server/session.ts:9324`). Legacy/broadcast
clients including `error` reason attention get it in `agent_stream` timeline rows instead.
**Permissions.** Outbound `["workspace.read","hub.execute"]` (`operation-permissions.ts:277`).
**How the app uses it.** `app/contexts/session-context.tsx:468` subscribes with
`{notifications: true}` and routes to `notifyAgentAttention` (`app/contexts/session-context.tsx:256`),
which drops `error` reasons, dedupes by `(agentId, timestamp)`, and sends an OS notification via
`sendOsNotification` (`app/utils/os-notifications.ts:144`). Foreground pushes stay in Notification
Center — no banner (`docs/notifications.md:53`).
**Gotchas.** Attention is acknowledged by deliberate focus/interaction, not by loading the
runtime; a completion arriving while focused stays unread until the next interaction, leaving the
pane does not clear it (`docs/agent-lifecycle.md:341`–`:344`). Error attention replaces unread
finished attention (`docs/agent-lifecycle.md:349`). `shouldNotify` is per-source — render the
badge, not the push decision, from it.

### 7.2 Clearing attention

**Clear agent(s)** — `clear_agent_attention` `messages.ts:3082`:
`{type, agentId: string|string[], requestId?: string}` (no response type; the daemon broadcasts
through `agent_update`/`agent_status` and `clear_agent_attention_response` is emitted
`messages.ts:5218`: `payload {requestId, agentId: string|string[], agents: AgentSnapshotPayloadSchema[]}`).

**Clear workspace** — `workspace.clear_attention.request` `messages.ts:2892`:
`{type, workspaceId: string|string[], requestId}` → `workspace.clear_attention.response`
(`messages.ts:5293`) `payload {requestId, workspaceId, clearedAgentIds: string[], results:
[{workspaceId, clearedAgentIds, success, error}], success, error}`.

**Mark unread** — `workspace.mark_unread.request` `messages.ts:2898`:
`{type, workspaceId, requestId}` → `workspace.mark_unread.response` (`messages.ts:5312`)
`payload {requestId, workspaceId, markedAgentId: string|null, success, error}`. The daemon
restores attention on the newest eligible root agent (`error` for lifecycle-`error`, `finished`
otherwise) without sending a new notification (`docs/agent-lifecycle.md:336`).

**Permissions.** `clear_agent_attention` `workspace.write` (`operation-permissions.ts:73`,
`:320`); `workspace.clear_attention.request|response` `workspace.write` (`:214`, `:461`);
`workspace.mark_unread.request|response` `workspace.write` (`:215`, `:462`).
**How the app uses it.** Focus/interaction clears: `app/hooks/use-agent-attention-clear.ts:41`
(`createAgentAttentionController`, `app/utils/agent-attention.ts:9`). OS notifications are
separate — clearing ≠ tapping; see `docs/notifications.md:10` for the tap path.

### 7.3 `client_heartbeat` — presence

**Purpose.** The daemon's view of which clients are present, app-visible, focused, and on what
agent/terminal — feeds the push planner above.

**Message** — `ClientHeartbeatMessageSchema` `messages.ts:3088`:
`{type, deviceType: "web"|"mobile", focusedAgentId: string|null, focusedTerminalId?:
string|null (default null, COMPAT `terminalFocusHeartbeat`), lastActivityAt: string (ISO),
appVisible: boolean, appVisibilityChangedAt?: string}`. Fire-and-forget; no response.

**Permissions.** `workspace.read` (`operation-permissions.ts:74`).
**How the app uses it.** 15 s interval + on visibility/focus changes:
`app/hooks/client-activity-tracker.ts:1`, `:51`; wired in
`app/hooks/use-client-activity.ts:54` and `:131`; recorded activity throttles to 5 s
(`app/hooks/client-activity-tracker.ts:2`).
**Gotchas.** Presence threshold is 180 s — a client whose socket is `OPEN` but JS-suspended
still counts as present until it misses heartbeats (`docs/architecture.md` handshake section,
`packages/server/src/server/agent-attention-policy.ts:3`). `focusedTerminalId` was added by
COMPAT `terminalFocusHeartbeat`; omit-handling on the wire is tolerant (defaults null).

### 7.4 `register_push_token` / `push.unregister.request`

**Register** — `RegisterPushTokenMessageSchema` `messages.ts:3127`:
`{type, token: string}`. **No response.** The daemon stores the token at
`$PASEO_HOME/push-tokens.json` (`docs/architecture.md:487`) and renews its lease on each
heartbeat tied to that token (`packages/server/src/server/session.ts:5306`).
**Unregister** — `push.unregister.request` `messages.ts:3132`: `{type, token, requestId}` →
`push.unregister.response` (`messages.ts:3138`): `payload {requestId}`. Gated for the sender on
`features.pushTokenRevocation` (`messages.ts:3875`) — the app only calls it when the connected
daemon advertises the flag (`app/push-notifications/internal/subscriptions.ts:93`).

**Permissions.** `register_push_token` / `push.unregister.request` / `push.unregister.response`:
`workspace.read` (`operation-permissions.ts:172`, `:168`, `:419`).
**How the app uses it.** `startSubscription` registers the Expo token on connect and on reconnect
(`app/push-notifications/internal/subscriptions.ts:59`–`:90`); revoke on sign-out/host removal
(`:92`–`:106`). The notification payload the user taps names `{serverId, workspaceId, agentId,
reason}` — see the iOS replay shape (`docs/notifications.md:36`); the tap must use
`navigateToAgent` and ignore the workspace hint — the agent may have moved
(`docs/notifications.md:10`).
**Gotchas.** Expo push tokens are per-app-install; the daemon sends via Expo's push API
(`packages/server/src/server/push/push-service.ts:31`). Payloads are minimal —
`buildAgentAttentionNotificationPayload` composes from the last assistant message / permission
request truncated to 220 chars (`packages/protocol/src/agent-attention-notification.ts:1`). Push
is only sent when *no* client is present (§7.1); a foregrounded app never gets a push banner.

### 7.5 Event delivery for attention and permission events

`session.events.set_subscription.request` (`messages.ts:3380`) selects which connection-scoped
event streams this socket wants — `SessionEventSubscriptionSchema` `messages.ts:3359`:
`project.update, providers_snapshot_update, agent_attention_required,
agent_permission_request, agent_permission_resolved, checkout_status_update,
script_status_update, workspace_setup_progress, agent.provider_subagents.update,
agent.background_work.update, terminal_attention_required, status.server_info,
status.daemon_config_changed, status.plugin_catalog_changed, status.plugin_settings_changed,
activity_log, hub.execution.agent.update, hub.execution.agent.stream`.

With `notifications: true`, the source is a notification target: it gets
`shouldNotify: true` exactly when the plan elects it (§7.1). Modern clients reach this through
`observeEvents` (`packages/client/src/daemon-client.ts:2849`); the app subscribes to
`["agent_attention_required","terminal_attention_required","agent_permission_request",
"agent_permission_resolved","agent.provider_subagents.update","checkout_status_update",
"status.server_info"]` (`app/contexts/session-context.tsx:468`).

## 8. Provider and model discovery

All discovery RPCs are correlated and return provider catalogs as of `fetchedAt`. The daemon
caches catalogs; explicit refresh is a separate RPC (§8.3).

### 8.1 `list_provider_models_request` / `list_provider_modes_request` / `list_provider_features_request`

**Requests** — `messages.ts:1877`, `messages.ts:1884`, `messages.ts:3114`:

`{type, provider: string, cwd?: string, requestId}` — models/modes; features takes
`draftConfig: {provider, cwd, modeId?, model?, thinkingOptionId?, featureValues?}` (`messages.ts:3105`)
instead of a bare provider.

**Responses** — `list_provider_models_response` (`messages.ts:6516`):
`payload {provider, models?: AgentModelDefinition[] (messages.ts:365), error?, fetchedAt, requestId}`;
`list_provider_modes_response` (`messages.ts:6527`): same shape with `modes?: AgentMode[]`;
`list_provider_features_response` (`messages.ts:6538`): same with `features?:
AgentFeature[] (messages.ts:360)`.

**Capability gates.** None beyond session admission; clients use these for draft pickers before an
agent exists.
**Permissions.** All three inbound `daemon.read`; responses `daemon.read`
(`operation-permissions.ts:125`, `:126`, `:124`, `:370`–`:372`).
**How the app uses it.** Draft pickers read the *snapshot* (§8.3) not these RPCs in steady state;
`list_provider_features_request` is used for the composer's feature toggles and custom-profile
forms: `app/hooks/use-draft-agent-features.ts:74`,
`app/agent-profiles/internal/use-profile-form-inputs.ts:54`. Client SDK:
`packages/client/src/daemon-client.ts:5760`, `:5778`, `:5794`.
**Gotchas.** Draft command/feature listing requires an explicit draft model — never resolve a
default model through catalog discovery (`docs/providers.md:118`). Mode IDs may be URIs
(`docs/providers.md:558`); dynamic discovery beats the static manifest (`docs/providers.md:560`).

### 8.2 `list_available_providers_request`

**Request** — `messages.ts:1891`: `{type, requestId}`.
**Response** — `list_available_providers_response` (`messages.ts:6555`):
`payload {providers: [{provider, available: boolean, error?: string|null}], error?, fetchedAt,
requestId}`.
**Permissions.** `daemon.read` both directions (`operation-permissions.ts:122`, `:368`).
**How the app uses it.** Onboarding and provider health surfaces; the app otherwise prefers the
snapshot view (`app/onboarding/internal/orchestration-setup.ts`). Client SDK:
`packages/client/src/daemon-client.ts:5809`.
**Gotchas.** `available` is binary availability (CLI present, auth checks pass) — it does not
imply models can be created; use the snapshot for that.

### 8.3 `get_providers_snapshot_request` / `refresh_providers_snapshot_request`

**Purpose.** One correlated call returning the full catalogue the pickers need: availability,
models, modes, features, icons — cached by the daemon per (scope, provider).

**Requests** — `messages.ts:1896`, `messages.ts:1904`:

`get_providers_snapshot_request {type, cwd?: string, ifNoneMatch?: string, requestId}` —
`ifNoneMatch` is a content hash from a previous snapshot; the daemon may answer `notModified`.
`refresh_providers_snapshot_request {type, cwd?, providers?: string[], requestId}` — forces
re-discovery; always succeeds immediately with an ack.

**Responses** — `get_providers_snapshot_response` (`messages.ts:6566`):
`payload {cwd?, entries: ProviderSnapshotEntrySchema[], compactSnapshot?:
CompactProviderSnapshotSchema, snapshotHash?: string, fetchedAt?: record<string,string>,
notModified?: boolean, generatedAt: string, requestId}` where an entry
(`ProviderSnapshotEntrySchema`, `messages.ts:379`) is `{provider, status:
"ready"|"loading"|"error"|"unavailable", enabled (default true), source?: "builtin"|"custom",
error?, models?: AgentModelDefinition[], modes?, fetchedAt?, label?, description?, iconSvg?,
defaultModeId?}`; the compact form (`messages.ts:412`) shares thinking option sets across models
and refers models to `thinkingSet` indices. `providers_snapshot_update` (daemon → subscribed
clients, `messages.ts:6581`) pushes the same shape incrementally.
`refresh_providers_snapshot_response` (`messages.ts:6595`): `payload {requestId,
acknowledged: boolean}`.

**Capability gates.** Compact wire form and `ifNoneMatch`/`snapshotHash` require the client
advertised `compact_provider_snapshots` (`CLIENT_CAPS.compactProviderSnapshots`,
`packages/protocol/src/client-capabilities.ts:37`; advertised in hello
`capabilities` (`messages.ts:8003`)). Content-hash announcements
(`provider_snapshot_references`) are client-side only; the daemon sends the directory-hash body
compactly (`docs/providers.md:162`). `features.providersSnapshot` (`messages.ts:3827`),
`features.providersSnapshotCwd` (`messages.ts:3834`), `features.providerUsageList`
(`messages.ts:3935`) and `features.connectedHosts` gate related surfaces. The app gates snapshot
usage on `features.providersSnapshot === true` (`app/hooks/use-providers-snapshot.ts:75`,
`app/screens/workspace/workspace-screen.tsx:1083`). Old daemons ignore `ifNoneMatch` and return a
full snapshot.
**Permissions.** `get_providers_snapshot_request` / response and
`refresh_providers_snapshot_request` / response: `["daemon.read","hub.execute"]`
(`operation-permissions.ts:110`, `:171`, `:355`, `:421`).
**How the app uses it.** `app/data/providers-snapshot.ts:66` (fetch w/ compact cache + hash
revalidation), `app/hooks/use-providers-snapshot.ts`, `app/data/push-router.ts:181` (push router
for out-of-band delivery), refresh on settings save and pull-to-refresh
(`app/data/providers-snapshot.ts:130`). Client SDK: `packages/client/src/daemon-client.ts:5821`,
`:6021`.
**Gotchas.** The server's provider keys never cross the wire: capable clients receive
directory-to-hash announcements; unknown hashes trigger a normal snapshot request
(`docs/providers.md:162`). Refresh invalidates and refreshes in actual execution context — every
connected client gets the refreshed view; configuration replacement invalidates only changed
providers (`docs/providers.md:174`). Snapshots are target-specific (scope `global` vs
`workspace` + `cwd`); equal keys share results and emit no transition if nothing changed
(`docs/providers.md:132`–`:187`). Selector opening may read a loading/stale snapshot without
forcing a probe — availability probing has a refresh deadline that concurrency-caps at four
catalogue probes per provider (`docs/providers.md:147`).

### 8.4 `provider_diagnostic_request`, `provider.usage.list.request`, `usage.list_reports.request`

**Diagnostics** — `provider_diagnostic_request` `messages.ts:1911` /
`provider_diagnostic_response` (`messages.ts:6604`): `payload {provider, diagnostic: string,
requestId}`. App: `app/components/provider-diagnostic-sheet.tsx:259`.

**Usage** — `provider.usage.list.request` `messages.ts:1917` /
`ProviderUsageListResponseMessageSchema` (`messages.ts:6666`):
`payload {providers: [{provider, status: "available"|"unavailable"|"error", ...}],
requestId}` — see the schema at `messages.ts:6613`–`:6666` for window/balance/detail shapes.
`usage.list_reports.request` `messages.ts:1922` streams `usage.list_reports.update`
(`messages.ts:6725`) per settled report then a terminal `usage.list_reports.response`
(`messages.ts:6729`); all three share `requestId`; no updates after the response
(`docs/rpc-namespacing.md:29`). App: `app/usage/queries.ts:75`.

**Permissions.** Diagnostics: `daemon.read` both directions (`operation-permissions.ts:166`,
`:416`); usage: `daemon.read` (`:164`, `:165`, `:413`–`:415`).
**Gotchas.** Usage data is read-only credential interpretation per provider — the app resolves
pins without provider-specific duration guesses (`docs/providers.md:192`). Account and
window identity are provider-owned; never merge two providers' numbers into one total without
labels.

## 9. Slash commands and agent commands

### 9.1 `list_commands_request`

**Purpose.** Enumerate the slash commands the composer can offer — provider-native commands plus
Paseo-injected ones.

**Request** — `messages.ts:3120`:
`{type, agentId: string, draftConfig?: ListCommandsDraftConfigSchema, requestId}` where the
draft config (`messages.ts:3105`) is `{provider, cwd, modeId?, model?, thinkingOptionId?,
featureValues?}`. Omitting `draftConfig` lists commands for the live agent; with it, lists the
commands a *draft* would have.

**Response** — `list_commands_response` (`ListCommandsResponseSchema`, `messages.ts:6741`):
`payload {agentId?, commands: AgentSlashCommand[] (messages.ts:6734 — {name, description,
argumentHint, kind?}), fetchedAt, requestId, error?: string|null}`.

**Capability gates.** None; draft listing requires an explicit draft model
(`docs/providers.md:118`).
**Permissions.** `daemon.read` both directions (`operation-permissions.ts:123`, `:379`).
**How the app uses it.** `app/agent-commands/use-query.ts:45` (fetch), rendered in the composer
across `app/agent-commands/index.tsx:60`. Client SDK: `packages/client/src/daemon-client.ts:6163`.
**Gotchas.** Pi discovers extension commands via RPC `get_commands` for the agent cwd; OMP uses
`get_available_commands` (`docs/providers.md:90`, `docs/providers.md:86`). OpenCode v2 needs config inventory
warmup before commands appear — empty inventory means "still warming", not "no commands"
(`docs/providers.md:96`). `kind` is provider-defined; clients must tolerate unknown kinds.
Client-side fixed commands (e.g. `/archive-agent`) are an app feature, not a wire feature — see
`app/client-slash-commands/index.ts:11`.

## 10. Image and file attachments

### 10.1 Inline image attachments

`ImageAttachmentSchema` `messages.ts:1287`: `{data: string (base64), mimeType: string}`. Present
on `send_agent_message_request` / `_request` (§2) and `create_agent_request` (§1). There is **no
size limit on the wire** — the 8 MiB WS outbound high-water mark applies per frame
(`docs/architecture.md:281`). The app pre-checks and compresses before encoding
(`app/composer/actions.ts:135`, `app/utils/encode-images`). Commands carrying images require the
provider model to accept them — Pi/OMP text-only models reject raw `images` and persist the
failure in JSONL history; materialize to a file and pass a path hint instead
(`docs/providers.md:76`).

### 10.2 Structured attachments (`AgentAttachmentSchema`)

`AgentAttachmentSchema` `messages.ts:1254` — discriminated union on `type`:

- `forge_change_request` (`ForgeChangeRequestAttachmentSchema`, `messages.ts:1157`): `{forge:
  string (default "github"), number, title, url, body?, projectPath?, baseRefName?,
  headRefName?, mimeType: "application/paseo-forge-change-request"}`
- `forge_issue` (`messages.ts:1182`): same minus refs; `mimeType:
  "application/paseo-forge-issue"`
- `github_pr` / `github_issue` (`messages.ts:1146`, `:1173`): **COMPAT** — legacy kinds retained
  when forge-neutral kinds shipped v0.2.0-beta.1; stop emitting after 2027-01-17.
- `text` (`TextAttachmentSchema`, `messages.ts:1203`): `{mimeType:"text/plain", text: string,
  title?, contextKind?: "chat_history" only, externalResource?}` — note this schema carries a
  `.transform`, and `AgentAttachmentsSchema` (`messages.ts:1278`) lenient-parses and **drops**
  unknown attachment kinds instead of rejecting the message.
- `review` (`ReviewAttachmentSchema`, `messages.ts:1236`): `{cwd, mode:
  "uncommitted"|"base"|"all", baseRef?, comments[]: {filePath, side, lineNumber, body, context:
  {hunkHeader, targetLine, lines[]}}, mimeType:"application/paseo-review"}`.
- `uploaded_file` (`UploadedFileAttachmentSchema`, `messages.ts:1245`): `{id, fileName,
  mimeType, size, path}` — `path` is a daemon-side path; content was uploaded out of band (§10.3).

**Wire purity gotcha.** `TextAttachmentSchema` and `AgentAttachmentsSchema` use
`.transform()`/lenient parse despite the "wire schemas are pure" rule
(`docs/protocol-compatibility.md:18`) — a native client must not replicate the lenient drop;
either implement identical normalization or reject unknown kinds loudly.

### 10.3 `file.upload.request` + binary frames

**Purpose.** Move bytes up to the daemon; the daemon stores them and hands back a
`uploaded_file` attachment reference for later messages.

**Request** — `messages.ts:3073`: `{type, fileName: string (min 1), mimeType: string (min 1),
size: int ≥ 0, modifiedAt: string (ISO), requestId}`. **No bytes on the JSON frame.**
**Byte flow.** Bytes stream as binary frames `FileBegin`/`FileChunk`/`FileEnd` correlated by
`requestId` — the upload bypasses the send queue entirely; chunks are 128 KiB by default; on the
native transport outbound chunking is disabled and admission errors surface as send failures
(`packages/client/src/daemon-client.ts:5628`–`:5714`, `docs/architecture.md:324`).
**Response** — `file.upload.response` (`FileUploadResponseSchema`, `messages.ts:6507`):
`payload {requestId, file: UploadedFileAttachmentSchema|null, error: string|null}`.
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:98`, `:342`).
**How the app uses it.** `app/composer/actions.ts:148` (`uploadFileAttachments`) — reads bytes,
enforces the app-side limit (`app/attachments/upload-limit.ts:1`), creates an `uploaded_file`
pill reference; send path attaches via `app/composer/actions.ts:222`. Terminal paste/drop uploads
go through the same RPC (`app/components/terminal-pane.tsx:878`).
**Gotchas.** The daemon must never fetch a user-provided URL on the host network — only client
chosen/acquired bytes (`messages.ts:1021`). Connections that drop mid-transfer reject the waiters
(`packages/client/src/daemon-client.ts:5705`). `modifiedAt` is required ISO — garbage in, file
rejected.

## 11. Subagents

Two species share the track UI: Paseo-managed subagents (normal agents with
`paseo.parent-agent-id`) and provider-managed children (descriptors only, read-only timelines).

### 11.1 Paseo subagents

Created through 1.1/1.2 with `callerAgentId` set (agent-scoped MCP `create_agent` always sets it)
or by a user explicitly. Membership rule: `parentAgentId === thisAgent.id && !archivedAt`
(`app/subagents/select.ts:85`), surfaced by the parent's subagents track pill. Lifecycle inherits
parent archive semantics with the two carve-outs (cross-workspace or open tab ⇒ detach instead of
archive) (`docs/agent-lifecycle.md:127`). No new wire messages — they are ordinary agents;
the label is the contract (`docs/agent-lifecycle.md:433`).

### 11.2 `agent.provider_subagents.list.request` / `agent.provider_subagents.timeline.get.request` / `agent.provider_subagents.update`

**List** — `ProviderSubagentListRequestMessageSchema` `messages.ts:2018`:
`{type, parentAgentId, requestId}` → `agent.provider_subagents.list.response`
(`ProviderSubagentListResponseMessageSchema`, `messages.ts:5037`):
`payload {requestId, parentAgentId, subagents: ProviderSubagentDescriptorPayloadSchema[]
(messages.ts:5015 — {id, parentAgentId, parentSubagentId?: string|null, provider, title,
description, status: "running"|"completed"|"failed"|"canceled", createdAt, updatedAt,
toolCallId, cwd?, subtitle?}), error}`.

**Timeline** — `ProviderSubagentTimelineRequestMessageSchema` `messages.ts:2038`:
`{type, parentAgentId, subagentId, requestId, direction?: "tail"|"before"|"after", cursor?:
{epoch, seq}, limit?}` → `agent.provider_subagents.timeline.get.response`
(`messages.ts:5092`) — paged rows with `projection:"projected"`, `reset`, `gap`, `window`,
cursors (same shape as the main timeline page — see timeline doc).

**Update (event)** — `ProviderSubagentUpdateMessageSchema` `messages.ts:5135`:
`payload` discriminated `kind`: `upsert {subagent}` | `timeline {parentAgentId, subagentId,
provider, item, timestamp, seq, epoch}` | `remove {parentAgentId, subagentId}`.

**Capability gates.** `CLIENT_CAPS.providerSubagents` (`packages/protocol/src/client-capabilities.ts:29`)
— the daemon sends the update stream and honors the list RPC only to clients advertising it
(`packages/server/src/server/session.ts:2037`, `:2048`). `features.providerSubagents`
(`messages.ts:3951`) is the server_info mirror; `features.providerSubagentNesting`
(`messages.ts:3960`+, COMPAT after v0.7) for `parentSubagentId`;
`features.projectedSubagentTimeline` for `projection:"projected"` (`messages.ts:3957`).
**Permissions.** List and timeline responses: `workspace.read`; update event: `workspace.read`
(`operation-permissions.ts:256`–`:258`, `:22`, `:25`).
**How the app uses it.** `app/subagents/provider-store.ts:92` (list on parent change + live
updates via `agent.provider_subagents.update` through `observeEvents`,
`app/contexts/session-context.tsx:474`); gated on `features.providerSubagents`
(`app/subagents/select.ts:183`).
**Gotchas.** A provider thread/session identifier is not a Paseo agent id — provider rows are
read-only; no archive/detach/rewind/fork (`docs/agent-lifecycle.md:370`). Claude background
tasks announce via the task protocol (`local_agent`/`local_workflow`); ambient `local_bash` work
and `skip_transcript` are never descriptors — a task never declared gets no descriptor by any
route (`docs/agent-lifecycle.md:380`). Provider-owned rows die with the provider session;
"Archive finished" hides them app-side only, in memory (`docs/agent-lifecycle.md:413`).

### 11.3 Background work — `agent.background_work.list.request` / `.stop.request` / `.update`

**List** — `messages.ts:2024`: `{type, agentId, requestId}` → `.response` `messages.ts:5061`:
`payload {requestId, agentId, items: AgentBackgroundWorkItemSchema[] (messages.ts:5047 — {id,
kind (open string; "shell"|"monitor"|…), description, command?, startedAt, canStop?, stopToken?}),
error}`.
**Stop** — `messages.ts:2030`: `{type, agentId, itemId, stopToken: string, requestId}` →
`.response` `messages.ts:5071`: `payload {requestId, agentId, itemId, error}`.
**Update (event)** — `AgentBackgroundWorkUpdateMessageSchema` `messages.ts:5083`:
`payload {subscriptionId?, agentId, items[]}` — replaces the agent's whole list per push.

**Capability gates.** `features.agentBackgroundWork` (`messages.ts:3953`),
`features.agentBackgroundWorkStop` (`messages.ts:3955`).
**Permissions.** List: `workspace.read`; stop: `["workspace.write","hub.execute"]`; update:
`workspace.read` (`operation-permissions.ts:23`, `:24`, `:259`–`:261`).
**How the app uses it.** Background-work chip on the agent screen; count also appears on the
snapshot (`AgentSnapshotPayloadSchema.backgroundWork.count`, `messages.ts:894`). Stop is offered
only when `canStop` and a `stopToken` are present.

### 11.4 Detach — see §4.7.

### 11.5 Fork context (adjacent)

`agent.fork_context.request` `messages.ts:2054` builds a `TextAttachmentSchema` of the
conversation up to a boundary (`boundaryCursor`/`boundaryMessageId`) for seeding a new agent;
`agent.fork_context.response` `messages.ts:5195` returns the attachment. Gated on
`features.agentForkContext` (`messages.ts:3947`) / `agentForkContextCursor` (`messages.ts:3949`).
Permissions `workspace.read` inbound and outbound
(`operation-permissions.ts:21`, `:255`). App: fork action in the chat (`app/hooks/use-fork-agent.ts:147`).

## 12. Daemon configuration and settings RPCs

Settings screens in the app read/patch one mutable config document. All of these are plain
request/response; most accept a partial patch and return the effective config.

### 12.1 `get_daemon_config_request`

**Request** — `messages.ts:1730`: `{type, requestId}`.
**Response** — `get_daemon_config_response` (`GetDaemonConfigResponseMessageSchema`,
`messages.ts:5345`): `payload {requestId, config: MutableDaemonConfigSchema (messages.ts:207)}`.
The schema is `.passthrough()` — unknown keys survive round-trips. Top-level keys (all optional
unless noted): `relay?` (`enabled` required if present), `mcp` (`{enabled?, injectIntoAgents}` —
`injectIntoAgents` **required**), `hostnames?`, `cors?`, `trustedProxies?`, `git?`, `app?`,
`catalogRefreshTimeoutMs?`, `usage?`, `browserTools` (default `{enabled:false}`), `providers`
(default `{}` — per-provider `{paseoTools?, enabled?, additionalModels?[]}`),
`metadataGeneration` (default `{providers: []}` — structured-generation provider chain for titles/
branch names), `autoArchiveAfterMerge` (default false), `enableTerminalAgentHooks` (default
false), `idleRuntimeCleanup?`, `resumeOnStartup?`, `resumePrompt?`, `appendSystemPrompt`
(default `""`), `terminalProfiles?`, `agentProfiles?` (array of `AgentProfileSchema`,
`packages/protocol/src/agent-profile.ts:12`), `skills?`, `pluginsEnabled?`, `plugins?`,
`features?` (speech settings, `packages/protocol/src/speech/rpc-schemas.ts:32`),
`envOverrides?`.
**Permissions.** `daemon.read` both directions (`operation-permissions.ts:109`, `:354`).
**How the app uses it.** `app/hooks/use-daemon-config.ts:30` (replica query, pushEvent
`status:daemon_config_changed`); consumers listed in §12.2. Client SDK:
`packages/client/src/daemon-client.ts:5846`.
**Gotchas.** The config is daemon-global, not per-workspace. `mcp.injectIntoAgents` is required in
the **full** config model (`MutableDaemonConfigSchema.mcp`) but the patch schema makes it optional —
never round-trip the whole config back as a patch. `agentProfiles` round-trips only if the daemon
supports them — see §12.10.

### 12.2 `set_daemon_config_request`

**Request** — `messages.ts:1735`: `{type, requestId, config: MutableDaemonConfigPatchSchema
(messages.ts:258)}`. The patch is **deep-partial and narrower than the read model**: it accepts
`relay, mcp {injectIntoAgents?}, usage, browserTools, providers, removeProviders, metadataGeneration,
autoArchiveAfterMerge, enableTerminalAgentHooks, idleRuntimeCleanup, resumeOnStartup, resumePrompt,
appendSystemPrompt, terminalProfiles, agentProfiles, pluginsEnabled, plugins, features` — and
**not** `hostnames`, `cors`, `trustedProxies`, `git`, `app`, `catalogRefreshTimeoutMs`, `skills` or
`envOverrides` (those are read-only through this RPC). `mcp.injectIntoAgents` is only *required* in
the full config model, never in the patch. `removeProviders: string[]` deletes provider entries;
`providers` is a partial record merge.
**Response** — `set_daemon_config_response` (`SetDaemonConfigResponseMessageSchema`,
`messages.ts:5473`): `payload {requestId, config: MutableDaemonConfigSchema}` — the effective
post-patch config.
**Events.** The daemon broadcasts `status` with `payload.status === "daemon_config_changed"`
(`DaemonConfigChangedStatusPayloadSchema`, `messages.ts:4119`) carrying the full config; this is
the pushEvent the app's replica query subscribes to (`app/hooks/use-daemon-config.ts:25`).
**Permissions.** `daemon.manage` both directions (`operation-permissions.ts:189`, `:438`).
**How the app uses it.** Every settings card: host page (`app/screens/settings/host-page.tsx:906`,
`:945`, `:986`, `:1424`), idle-runtime-cleanup (`app/screens/settings/idle-runtime-cleanup-card.tsx:18`),
restart recovery (`app/screens/settings/restart-recovery-card.tsx:23`), paseo-tools
(`app/screens/settings/paseo-tools-card.tsx:11`), browser tools
(`app/screens/settings/browser-tools-card.tsx:18`), metadata generation
(`app/screens/settings/metadata-generation-page.tsx:20`), providers section
(`app/screens/settings/providers-section.tsx:363`), voice page
(`app/screens/settings/voice/voice-page.tsx:73`), pair-device (`app/desktop/components/pair-device-section.tsx:49`,
`:72`), plugins page (`app/screens/settings/plugins-page.tsx:278`), profile migration
(`app/agent-profiles/migration/index.ts:208`), orchestration setup
(`app/onboarding/internal/orchestration-setup.ts:42`). Client SDK:
`packages/client/src/daemon-client.ts:5951` (`patchDaemonConfig`).
**Gotchas.** Unknown keys in patches are preserved (passthrough) — a client that round-trips a
config it doesn't understand will persist garbage back if it also writes known keys. Prefer
surgical patches. `idleRuntimeCleanup`/`resumeOnStartup` apply live; TOML/JSON file edits need
`daemon.config.reload.request` (`docs/agent-lifecycle.md:52`).

### 12.3 `daemon.config.reload.request`

**Request** — `messages.ts:1494`: `{type, requestId}`.
**Response** — `daemon.config.reload.response` (`DaemonConfigReloadResponseSchema`,
`messages.ts:5451`): `payload {requestId, appliedPaths: string[], restartRequiredPaths:
string[], overrideControlledPaths: string[]}`.
**Capability gates.** `features.daemonConfigReload` (`messages.ts:3869`).
**Permissions.** `daemon.manage` both directions (`operation-permissions.ts:81`, `:324`).
**How the app uses it.** Not currently called by the app; the CLI calls it after editing
`config.json`. Use it, not restart, for config-file changes.
**Gotchas.** Terminal worker config does not hot-reload — see `docs/architecture.md` storage
section; restart-required paths are reported explicitly, don't guess.

### 12.4 `read_project_config_request` / `write_project_config_request`

**Requests** — `messages.ts:1741`, `:1747`: `{type, requestId, repoRoot: string, ...}`; write adds
`config: PaseoConfigRawSchema, expectedRevision: PaseoConfigRevision | null` for optimistic
concurrency — where `PaseoConfigRevision = {mtimeMs: number, size: number}`
(`packages/protocol/src/paseo-config-schema.ts:99-102`), **an object, not a string**.
**Responses** — `read_project_config_response` / `write_project_config_response`
(`messages.ts:5483`, `:5505`): sequential `payload` union `{requestId, repoRoot, ok: true,
config: PaseoConfigRaw | null, revision: PaseoConfigRevision | null,
hasUncommittedWorktreeSetupChanges?}` | `{requestId, repoRoot, ok: false, error:
ProjectConfigRpcErrorSchema}` — deliberately not boolean-discriminated (zod-aot miscompile,
`messages.ts:5485`). Read returns `config`/`revision` as *required-nullable*; write returns them
non-null. Error codes: `project_not_found`, `invalid_project_config`, `stale_project_config`
(with `currentRevision`), `write_failed`.
**Permissions.** `workspace.read` / `workspace.write` (`operation-permissions.ts:169`, `:235`).
**How the app uses it.** Workspace setup panel reads/writes `paseo.json`-style configs at the
repo root. Revisions protect against two clients racing the same file.
**Gotchas.** The write carries `expectedRevision` — always pass the one you read, or you get an
`ok:false` conflict payload, not an exception.

### 12.5 `daemon.get_status.request`

**Request** — `messages.ts:1484`: `{type, requestId}`.
**Response** — `daemon.get_status.response` (`DaemonGetStatusResponseSchema`, `messages.ts:5355`):
`payload {requestId, serverId, version?: string|null, pid: number, nodePath: string,
startedAt?: string|null, listen: string|null, relay?: {enabled, endpoint, publicEndpoint,
useTls, publicUseTls}|null, providers: [{provider, available, error?}],
terminalCleanupUnconfirmed?: [{pid, role, reason, detail}], terminalsUnavailable?: string}`.
**Capability gates.** `features.daemonStatusRpc` (`messages.ts:3867`) — added v0.1.76;
treat absence as "old host".
**Permissions.** `daemon.read` both directions (`operation-permissions.ts:83`, `:326`).
**How the app uses it.** Host page diagnostics (`app/screens/settings/host-page.tsx:637`,
`:813`); restart confirmation flow reads it after `restart_server_request`. Client SDK:
`packages/client/src/daemon-client.ts:5858`.

### 12.6 `daemon.get_pairing_offer.request`

**Request** — `messages.ts:1489`: `{type, requestId}`.
**Response** — `daemon.get_pairing_offer.response` (`DaemonGetPairingOfferResponseSchema`,
`messages.ts:5439`): `payload {requestId, url: string, qr?: string|null, relayEnabled: boolean}`.
**Permissions.** `access.manage` — this is a credential-issuance path (`operation-permissions.ts:82`,
`:325`).
**How the app uses it.** Pair-device screen (`app/desktop/components/pair-device-section.tsx:59`).
**Gotchas.** The URL embeds a single-use pairing token; treat the QR/url as secret material.
`relayEnabled` tells you if the offer routes via relay vs direct.

### 12.7 `restart_server_request` / `shutdown_server_request`

**Restart** — `messages.ts:1961`: `{type, reason?, requestId, killTerminals?: boolean}`.
Terminals survive restart only if the daemon advertises `features.terminalsSurviveRestart`
(`messages.ts:3945`); older daemons close terminals regardless.
**Shutdown** — `messages.ts:1970`: `{type, requestId, keepTerminals?: boolean}`.
**Responses.** Both answers ride the `status` message: `restart_requested`
(`RestartRequestedStatusPayloadSchema`, `messages.ts:4106` — includes `clientId`) /
`shutdown_requested` (`messages.ts:4113`). There is no dedicated response type.
**Capability gates.** `features.terminalsSurviveRestart` (`messages.ts:3945`) gates the terminal
survival semantics only.
**Permissions.** `daemon.manage` both directions (`operation-permissions.ts:173`, `:194`).
**How the app uses it.** Settings → About → Restart/Shutdown:
`app/screens/settings/host-page.tsx:634`, `:810`; gated behind destructive confirmations.
**Gotchas.** Restart preserves terminals only when `killTerminals !== true` AND the daemon
supports the flag; `shutdown_server_request` closes terminals unless `keepTerminals: true` is
honored. Restart requires `features.terminalsSurviveRestart` to be meaningful — always pass
`killTerminals` explicitly on mobile.

### 12.8 `daemon.update.request`

**Request** — `messages.ts:1978`: `{type, requestId}`.
**Response** — `daemon.update.response` (`DaemonUpdateResponseSchema`, `messages.ts:6906`):
`payload {requestId, success: boolean, error: string|null, previousVersion: string|null, newVersion: string|null}`; progress
streams as `daemon.update.progress` events (`messages.ts:6919`).
**Capability gates.** `features.daemonSelfUpdate` (`messages.ts:3943`).
**Permissions.** `daemon.manage` both directions (`operation-permissions.ts:84`, `:328`).
**How the app uses it.** Settings → About → Update host (`app/screens/settings/host-page.tsx:810`).

### 12.9 `diagnostics.request`

**Request** — `messages.ts:1522`: `{type, requestId}`.
**Response** — `diagnostics.response` (`DiagnosticsResponseSchema`, `messages.ts:5463`):
`payload {requestId, diagnostic: string}`.
**Capability gates.** `features.daemonDiagnostics` (`messages.ts:3941`).
**Permissions.** `daemon.read` both directions (`operation-permissions.ts:86`, `:329`).
**How the app uses it.** App diagnostic sheet (`app/components/app-diagnostic-sheet.tsx:291`).
**Gotchas.** The payload is one opaque string — render it verbatim in a scrollable sheet; do not
try to parse it. Contains paths and config; treat it as support-bundle material.

### 12.10 Profiles and structured generation (config, not RPC)

Agent profiles live inside `get/set_daemon_config_request` as
`config.agentProfiles: AgentProfileSchema[]` (`packages/protocol/src/agent-profile.ts:12`):
`{id, name, icon? (client icon-registry key), color?, provider, model?, modeId?,
thinkingOptionId?, featureValues?, notes?}`. Gate the UI on `features.agentProfiles`
(`messages.ts:4028`) — old daemons parse persisted config strictly and silently drop the key, so
a save would appear to succeed and vanish (comment at `messages.ts:4026`). Capacity for applying
profiles to running agents is `features.agentConfigApply` (`messages.ts:4030`, §3.5).
`metadataGeneration` (§12.1) configures title/branch-name generation providers; both are consumed
via the config RPCs only.

### 12.11 Speech settings in config

`config.features.dictation` / `config.features.voiceMode` hold STT/TTS/LLM/turn-detection
selection (`packages/protocol/src/speech/rpc-schemas.ts:32`);
patch shape `SpeechSettingsPatchSchema` (`:101`) allows null-clearing individual fields. Voice UI
is gated on `features.speechSettings` (`messages.ts:3871`). The app edits these from
`app/screens/settings/voice/voice-page.tsx:73`.

## 13. Voice and dictation

Voice is a wire feature: dictation is client→daemon PCM streaming with daemon-side STT; voice
mode is full duplex with synthesized speech back to the client.

### 13.1 `set_voice_mode`

**Request** — `messages.ts:1136`: `{type, enabled: boolean, agentId?: string,
requestId?: string}` — `agentId` optional; without it the daemon toggles the voice lane for the
session's active agent.
**Response** — `set_voice_mode_response` (`SetVoiceModeResponseMessageSchema`,
`messages.ts:2304`): `payload {requestId, enabled, agentId: string|null` (required key, may be
`null`)`, accepted: boolean,
error: string|null, reasonCode?: string, retryable?: boolean, missingModelIds?: string[]}` —
`reasonCode`/`missingModelIds` explain why a turn-detection or model requirement failed
(e.g. no STT/TTS model downloaded).
**Events it causes.** `audio_output` chunks (§13.4), `voice_input_state`, `transcription_result`;
`assistant_chunk` telemetry.
**Permissions.** `workspace.write` both directions (`operation-permissions.ts:193`, `:442`).
**How the app uses it.** `app/voice/voice-runtime.ts:573` (enable on focus of the active agent),
`app/screens/settings/voice/voice-page.tsx:73` (persist the toggle in config). Client SDK:
`packages/client/src/daemon-client.ts:4502`.
**Gotchas.** `hello.capabilities.voice` (`messages.ts:7992`) is how a client advertises it *wants*
voice; the daemon's own voice readiness is in `server_info.capabilities.voice/dictation`
(`ServerVoiceCapabilitiesSchema`, `messages.ts:3755`) with per-feature `{enabled, reason}`.

### 13.2 `voice_audio_chunk` (client → daemon)

`VoiceAudioChunkMessageSchema` `messages.ts:965`: `{type, audio: string (base64), format: string,
isLast: boolean}` — legacy flat streaming path. New clients use the dictation stream (§13.3).
**Permissions.** `workspace.write` (`operation-permissions.ts:212`).

### 13.3 Dictation stream — start/chunk/finish/cancel + ack/partial/final/error

**Purpose.** Lossless, resumable STT capture: monotonically sequenced base64 PCM chunks,
acknowledged incrementally so a flaky network never loses audio.

**Requests (client → daemon)** — all `workspace.write`
(`operation-permissions.ts:87`–`:90`):

- `dictation_stream_start` `messages.ts:1759`: `{type, dictationId, format}` — e.g.
  `"audio/pcm;rate=16000;bits=16"`.
- `dictation_stream_chunk` `messages.ts:1765`: `{type, dictationId, seq: int ≥ 0, audio:
  base64, format}`.
- `dictation_stream_finish` `messages.ts:1773`: `{type, dictationId, finalSeq: int ≥ 0}`.
- `dictation_stream_cancel` `messages.ts:1779`: `{type, dictationId}`.

**Events (daemon → client)**:

- `dictation_stream_ack` (`messages.ts:3705`): `{dictationId, ackSeq}` — `ackSeq` is the highest
  contiguous received seq.
- `dictation_stream_finish_accepted` (`messages.ts:3713`): `{dictationId, timeoutMs}` —
  daemon will finish within `timeoutMs` or emit an error.
- `dictation_stream_partial` (`messages.ts:3721`): `{dictationId, text}` — interim hypothesis.
- `dictation_stream_final` (`messages.ts:3729`): `{dictationId, text, debugRecordingPath?}` —
  terminal; the final string to place in the composer.
- `dictation_stream_error` (`messages.ts:3738`): `{dictationId, error, retryable: boolean,
  reasonCode?, missingModelIds?: string[], debugRecordingPath?}`.

**Capability gates.** `features.speechSettings` gates the settings UI only (`messages.ts:3871`);
the stream itself is un-gated. Daemon-side STT requires a working dictation provider — inspect
`server_info.capabilities.dictation` before offering the mic button
(`messages.ts:3760`).
**Permissions.** All five outbound dictation events: `workspace.write`
(`operation-permissions.ts:330`–`:334`).
**How the app uses it.** `app/dictation/dictation-stream-sender.ts:202` (start), `:281`–`:285` (ack
handling); drains with a 30 s idle timeout (`app/dictation/dictation-stream-sender.ts:6`).
Client SDK: `packages/client/src/daemon-client.ts:4537` (`startDictationStream`),
`:4590` (`sendDictationStreamChunk`), `:4600` (`finishDictationStream`), `:4752`
(`cancelDictationStream`).
**Gotchas.** `seq`/`ackSeq` are independent monotonic counters per `dictationId` — reuse a fresh
`dictationId` per utterance; a reset without cancel is a leak on the daemon
(`app/dictation/dictation-stream-sender.ts:39`). `finishDictationStream` resolves with the
final text and is the only way to know STT completed; `transcription_result` (§13.4) is the
legacy equivalent.

### 13.4 `assistant_chunk`, `audio_output`, `transcription_result`, `voice_input_state`, `audio_played`

- `audio_played` (client → daemon, `messages.ts:976`): `{type, id}` — marks an output chunk
  consumed; `workspace.write`. The app echoes it from the audio engine after playback
  (`app/contexts/session-context.tsx:327`).
- `assistant_chunk` (daemon → client, `messages.ts:3663`): `payload {chunk: string}` — streamed
  TTS text for the voice lane; `workspace.read` (`operation-permissions.ts:286`).
- `audio_output` (daemon → client, `messages.ts:3670`): `payload {audio: base64, format: string,
  id: string, isVoiceMode: boolean, groupId?: string, chunkIndex?: int, isLastChunk?: boolean}` —
  `isVoiceMode` is drift protection: drop audio tagged for a lane you're not in
  (`packages/client/src/daemon-client.ts:4502` area — see app `app/voice/voice-runtime.ts`).
  `workspace.write` outbound (`operation-permissions.ts:287`).
- `transcription_result` (daemon → client, `messages.ts:3683`): `payload {text, language?,
  duration?, requestId, avgLogprob?, isLowConfidence?, byteLength?, format?,
  debugRecordingPath?}` — legacy non-streaming result; the stream's final message is authoritative.
  `workspace.write` outbound (`operation-permissions.ts:456`).
- `voice_input_state` (daemon → client, `messages.ts:3698`): `payload {isSpeaking: boolean}` —
  turn-detection VAD state for the mic indicator; `workspace.write` (`operation-permissions.ts:459`).

### 13.5 `speech.local_models.list.request` / `.download.request` / `.delete.request`

**Purpose.** Manage daemon-resident STT/TTS model files (local provider).

**Requests** — `packages/protocol/src/speech/rpc-schemas.ts:161`, `:166`, `:172`:
`{type, requestId[, modelId]}`.
**Responses** — `.list.response` (`:178`): `payload {requestId, models: LocalSpeechModelSchema[]
(id, kind, label, description, languages, downloadSizeBytes, isDefault, inUse, status,
receivedBytes?, totalBytes?, error?), error}`; `.download.response` (`:188`): `{requestId,
error}` — resolves when the download *starts*; poll list for progress; `.delete.response`
(`:196`).
**Permissions.** List: `daemon.read`; download/delete: `daemon.manage`
(`operation-permissions.ts:190`–`:192`).
**How the app uses it.** Voice settings → Local models section; poll the list while any model
is `downloading`/`extracting`. Client SDK: `packages/client/src/daemon-client.ts:5965`–`:5991`.

## 14. Schedules and heartbeats

### 14.1 Schedules

**Purpose.** Cron-like recurring agent runs managed by the daemon
(`docs/architecture.md:103` — `server/schedule/`).

All schedule RPCs are **slash-namespaced flat names**, not dotted — `schedule/create`,
`schedule/list`, … — a deliberate deviation from `docs/rpc-namespacing.md` predating it.

| Operation | Request (`packages/protocol/src/schedule/rpc-schemas.ts:27`) | Response |
|---|---|---|
| `schedule/create` | `{type, requestId, prompt: string (min 1), name?, cadence: ScheduleCadenceSchema, target: ScheduleCreateTargetSchema, maxRuns?: int>0, expiresAt?: string, runOnCreate?}` (`:27`) | `schedule/create/response` `{requestId, schedule: ScheduleSummary|null, error}` (`:102`) |
| `schedule/list` | `{type, requestId}` (`:39`) | `schedule/list/response` (`:111`) |
| `schedule/inspect` | `{type, requestId, scheduleId}` (`:44`) | `schedule/inspect/response` (`:120`) — full `StoredSchedule` incl. `runs[]` (`types.ts:58`) |
| `schedule/logs` | `{type, requestId, scheduleId}` (`:50`) | `schedule/logs/response` (`:129`) |
| `schedule/pause` | `{type, requestId, scheduleId}` (`:56`) | `schedule/pause/response` (`:138`) |
| `schedule/resume` | `{type, requestId, scheduleId}` (`:62`) | `schedule/resume/response` (`:147`) |
| `schedule/delete` | `{type, requestId, scheduleId}` (`:68`) | `schedule/delete/response` (`:156`) |
| `schedule/run-once` | `{type, requestId, scheduleId}` (`:74`) | `schedule/run-once/response` (`:165`) |
| `schedule/update` | `{type, requestId, scheduleId, name? (null clears), prompt?, cadence?, newAgentConfig?: {provider?, model? (null clears), modeId? (null clears), thinkingOptionId? (null clears), archiveOnFinish?, isolation?: "local"\|"worktree", cwd?}, maxRuns? (null clears), expiresAt? (null clears)}` (`:90`) | `schedule/update/response` (`:174`) |

`ScheduleCadenceSchema` (`packages/protocol/src/schedule/types.ts:7`): `{type:"every",
everyMs: int>0}` | `{type:"cron", expression: string (min 1), timezone?}`. `ScheduleTargetSchema`
(`types.ts:20`): `{type:"agent", agentId}` | `{type:"new-agent", config: {provider, cwd,
modeId?, model?, thinkingOptionId?, archiveOnFinish?, isolation?: "local"|"worktree", title?,
providerOptions?, featureValues?, systemPrompt?, mcpServers?}}` — plus a `"self"` variant on the
create schema only (`rpc-schemas.ts:12`). `StoredScheduleSchema`/`ScheduleSummarySchema` in
`types.ts:58`/`:76`; runs are `{id, scheduledFor, startedAt, endedAt, status:
"running"|"succeeded"|"failed", agentId: uuid|null, workspaceId?, output, error}` (`types.ts:45`).

**Events.** None — schedules have no live push; poll `schedule/list` / `schedule/logs`.
**Permissions.** Every schedule op inbound and outbound: `automation.manage`
(`operation-permissions.ts:175`–`:183`, `:423`–`:432`).
**How the app uses it.** Schedules screen: `app/hooks/use-schedule-mutations.ts:123` (create),
`:134` (update); aggregated cross-host list: `app/schedules/aggregated-schedules.ts:98`. Client
SDK: `packages/client/src/daemon-client.ts:6947` (`scheduleCreate`), `:6964` (`scheduleList`),
`:6974` (`scheduleInspect`), `:7040` (`scheduleUpdate`), `:6985`–`:7039` (pause/resume/delete/
runOnce).
**Gotchas.** `schedule/create` with `runOnCreate: true` dispatches the first run immediately and
returns after it *starts*, not after it finishes. `expiresAt`/`maxRuns` are soft limits enforced
at dispatch time. New agents from `target.type === "new-agent"` inherit their cwd exactly — the
daemon does not expand `~`. `self`/`agent` targets require the target agent to exist at dispatch
time; `agent` targets may point at archived agents (they are resumed). A schedule run failure is
a `ScheduleRun.status = "failed"` with `error` — it does not crash the daemon.

### 14.2 Heartbeats

Heartbeats are **not a wire feature**. They are schedules with `target: {type:"agent",
agentId: <self>}` created from inside an agent (`packages/cli/src/commands/heartbeat/index.ts:73`,
`:80`); the CLI requires `PASEO_AGENT_ID` and refuses to run outside an agent
(`:35`). The daemon-side catalog entry (`create_heartbeat`/`delete_heartbeat`) is an agent tool,
not a client RPC. All semantics are §14.1.

### 14.3 Loops (legacy, removed)

`loop/run|list|inspect|logs|stop` (`packages/protocol/src/loop/rpc-schemas.ts`) were removed in
v0.3.0; schemas remain only to parse mixed-version peers until 2027-02-09
(`packages/protocol/src/loop/rpc-schemas.ts:4`). Do not implement them.

## 15. Minimal set for a v1 client

Priorities first. Each item is the smallest sufficient subset.

**Must have (agents are useless without these)**

1. Handshake: `hello` with `clientType:"mobile"`, `protocolVersion`, capabilities
   `{selectiveAgentTimeline, reasoningMergeEnum, explicitEventSubscriptions,
   ownedSubscriptions, providerSubagents, backgroundAgents, compactProviderSnapshots}`
   (`messages.ts:7973`; defaults in `packages/client/src/connection/index.ts:127`); read
   `server_info` for `features`/`permissions` (`messages.ts:3796`).
2. `fetch_agent_request` + `fetch_agents_request` to paint the sidebar/list
   (`messages.ts:1453`, `:1329`) — or directory sync if you ship it.
3. `create_agent_request` for new threads (accept 1.1's legacy shape first; add 1.2 receipts
   later) — `messages.ts:1819`.
4. `send_agent_message_request` with `messageId` always set — `messages.ts:1460`.
5. `agent_update` subscription (upsert/remove) as the liveness bus — `messages.ts:4381`.
6. `agent_permission_request` subscription + `agent_permission_response` — `messages.ts:5527`,
   `:2318`. Meanwhile render `pendingPermissions` from snapshots.
7. `set_agent_mode_request`, `set_agent_model_request`, `set_agent_thinking_request`,
   `set_agent_feature_request` (+ `agent.config.apply.request` if you do profiles) —
   `messages.ts:2062`, `:2082`, `:2094`, `:2106`, `:2139`.
8. `archive_agent_request` (soft delete) — `messages.ts:999`.
9. `cancel_agent_request` — the stop button; `requestId` is **optional** on this request and a
   response without `requestId` is legal — `messages.ts:1955`, response `messages.ts:5208`.
10. `agent_attention_required` subscription with `{notifications: true}`, then either
   notification taps or an in-app badge; `clear_agent_attention` on deliberate focus —
   `messages.ts:5172`, `:3082`.

(Timeline reading is a separate doc, but items 4–6 and 9 are useless without the
`fetch_agent_timeline_request` / `agent_stream` pair.)

**Should have**

11. `get_providers_snapshot_request` for the model/mode/thinking pickers — `messages.ts:1896`.
12. `list_commands_request` for the slash menu — `messages.ts:3120`.
13. `update_agent_request` for rename/labels — `messages.ts:1012`.
14. `client_heartbeat` every 15 s with `focusedAgentId` — `messages.ts:3088`.
15. `register_push_token` if you want notifications while foregrounded elsewhere — `messages.ts:3127`.
16. `get_daemon_config_request` / `set_daemon_config_request` for one Settings page —
    `messages.ts:1730`, `:1735`.

**Can defer**

17. `agent.config.apply.request`, profiles, fork context, rewind, detach, provider-subagents
    track, background work, schedules, dictation/voice, `daemon.get_status`, Hub RPCs,
    `diagnostics.request`.

Skip entirely for v1: timeline internals (separate doc), terminals, git/checkout RPCs, plugins,
chat/loops, worktrees beyond the `worktree` creation target, catalog replica sync.

Verified: agent/permission/settings wire facts re-derived from source; 196 facts checked, 24 corrected.
