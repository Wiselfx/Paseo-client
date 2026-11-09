# 10 — Attention notifications

What Paseo's own app does when an agent or terminal needs you, what this iPhone client can do
about it without a relay or a push server, and what this ticket implements. Citations are
`path:line` in `/home/paseo/dev/paseo-reference` (the daemon + app monorepo) and this worktree.

## What upstream notifies on

One daemon event per transition, `agent_attention_required`
(`packages/protocol/src/messages.ts:5172`). The payload carries the agent, one of
`finished | error | permission`, an ISO timestamp, `shouldNotify`, and an optional
`notification { title, body, data { serverId, workspaceId?, agentId, reason } }`
(`messages.ts:5172-5190`; documented in `docs/research/04-protocol-agents-permissions-settings.md:644-667`).

- **Finished** — the turn ended and the agent has an answer. The title is "Agent finished"; the
  body previews the last assistant message, stripped of Markdown and truncated to 220 chars
  (`packages/protocol/src/agent-attention-notification.ts:1`, `:172-201`).
- **Permission** — the provider is waiting on a tool/plan/question approval. Title "Agent needs
  permission"; body is the request's title/description or a compact input preview
  (`agent-attention-notification.ts:106-131`, `:172-201`).
- **Error** — title "Agent needs attention", body "Encountered an error.", but the app never posts
  it: pure errors are dropped before the OS notification (`packages/app/src/contexts/session-context.tsx:266-268`).
- **Terminal attention** — `terminal_attention_required` with its own title, body,
  `shouldNotify`, terminal id, cwd and optional workspace id
  (`packages/protocol/src/messages.ts:6902`; feed in
  `packages/app/src/contexts/session-context.tsx:644-662`). Same notification path as agents.

The daemon decides, not the app. `computeNotificationPlan`
(`packages/server/src/server/agent-attention-policy.ts:42-84`) picks the most recently present
client (presence seen within 180 s, `:3`) as the in-app recipient and only allows push when no
client is present; `error` is not push-eligible (`:86-90`). The elected client gets
`shouldNotify: true`, everyone else false (`packages/server/src/server/websocket-server.ts:2932-2985`).
A present, app-visible client focused on that agent suppresses the notification entirely.

## What upstream suppresses and dedupes

`notifyAgentAttention` (`packages/app/src/contexts/session-context.tsx:256-309`):

1. drop `reason === "error"` (`:266-268`);
2. drop when the app is actively visible and the focused agent is this agent (`:270-274`);
3. keep `attentionNotifiedRef: agentId → timestamp`; an event whose timestamp is not newer is
   dropped (`:276-283`) — this is the dedupe for duplicate/out-of-order delivery;
4. ignore the daemon's workspace hint for routing; use the agent's current workspace
   (`:284-288`, and `docs/notifications.md:9-12`);
5. post the daemon copy when present, otherwise build the fallback title/body above
   (`:289-306`).

The terminal feed only checks `shouldNotify` and forwards the daemon's title/body
(`session-context.tsx:644-662`). It has no per-terminal timestamp dedupe; the daemon emits one
message per transition.

## Tap routing

Upstream parses flat `userInfo` into an agent, terminal or host target
(`packages/app/src/notification-open/model.ts:16-31`) and routes agent taps by agent id, ignoring
any stale workspace hint (`docs/notifications.md:9-12`). Terminal taps use
`workspace + terminal + cwd` and open the workspace/terminal
(`notification-open/model.ts:16-22`, `:52-59`).

The router waits until navigation is ready before dispatching, dedupes handled notification ids
in-process, and acknowledges the response so a cold launch cannot reopen the same agent
(`notification-open/model.ts:37-52`; readiness in
`packages/app/src/notification-open/react/index.tsx:14-65`). Native startup takes
`getLastNotificationResponseAsync` and clears it after dispatch
(`packages/app/src/notification-open/source.native.ts:27-35`). Foreground remote pushes stay in
Notification Center without a banner (`docs/notifications.md:53-55`).

## What iOS allows without a relay or our own push server

**Can work — local notifications over the live socket.** While the app process is alive (foreground,
or briefly in the background before suspension), `UNUserNotificationCenter` can post a local
notification from a daemon event, show it in Notification Center, and route a tap back into the
app. That is the whole scope of this ticket.

**Cannot work — true remote push while the app is closed.** That requires all of:

1. an app with an APNs-capable entitlement and a provider server holding an APNs key/token;
2. a device token registered with the sender;
3. a sender (the daemon or relay) that knows that token.

This client has none. There is no APNs entitlement or push provider
(`App/project.yml`, `App/Resources/Info.plist`), no relay, and no pairing flow. The daemon's push
path is Expo push (`packages/server/src/server/push/push-service.ts:1-60`); the reference app gets
an Expo token from an EAS project (`packages/app/src/push-notifications/internal/subscriptions.ts:16-73`)
and registers it through `register_push_token` — a call this client already models but never makes
(see PARITY). Upstream's own native path is push-only: `sendOsNotification` returns false on
native (`packages/app/src/utils/os-notifications.ts:144-149`), and `ensureOsNotificationPermission`
returns false there too (`:91-96`).

**Background limits.** iOS suspends a normal app shortly after it leaves the foreground; a
suspended process has no WebSocket, so no daemon event can arrive. `BGAppRefreshTask` is
opportunistic, roughly 30 s, and is for fetching, not for keeping a socket alive or receiving
agent traffic. Without a background mode such as audio/VoIP (not appropriate and not declared
here), the practical window is "foreground, plus the short time before suspension". Local
notifications already scheduled before suspension still deliver; new ones cannot be created until
the app runs again. A notification that needs a fresh daemon fetch at tap time will get it when
the app relaunches and reconnects.

**Consequences.** An agent that finishes while the app is fully closed produces no notification.
The in-app badge/status dot is still correct on the next launch, because the agent snapshot carries
`requiresAttention` / `attentionReason`.

## This client's implementation

- **Protocol.** The running daemon (v0.15.2) delivers attention to legacy clients as an
  `attention_required` event inside `agent_stream`, carrying the full notification plan
  (`packages/server/src/server/websocket-server.ts:2960-2984`); the modern top-level
  `agent_attention_required` message goes only to sources that advertise
  `explicit_event_subscriptions` (`packages/server/src/server/session.ts:9315-9333`). This client
  does not advertise it (`PaseoCore/Sources/PaseoProtocol/Handshake.swift`), so the legacy shape is
  the one that matters. A legacy source only receives attention for agents it is subscribed to
  (`packages/server/src/server/websocket-server.ts:2907-2912`), and this app holds a live
  agent-directory subscription (`HostSession.refreshAgents` uses `FetchAgentsRequest(subscribe:)`),
  which covers every listed agent. `AgentStreamPayload` now decodes the plan alongside the event
  (`PaseoCore/Sources/PaseoProtocol/AgentTimeline.swift`, `AgentAttention.swift`); an unreadable
  plan never fails the stream.
- **Store.** `AttentionCenter` (`PaseoCore/Sources/PaseoStore/AttentionCenter.swift`) applies the
  rules above: error dropped, `shouldNotify` honoured, focused agent suppressed, per-destination
  timestamp watermark, one queued intent per agent/terminal (newer replaces older). It stores no
  daemon connection and posts nothing; the app drains `pending`.
  `HostSession` feeds it from `agent_stream` attention events and `terminal_attention_required`
  (`HostSession.swift:231-240`, `:297-305`), including agents with no open conversation.
  `AttentionTarget` has a flat `userInfo` round trip for tap routing.
- **App.** `App/Sources/NotificationCoordinator.swift` is the only UserNotifications code: picks
  the delegate, asks permission when the first intent arrives or Settings turns the toggle on,
  posts local notifications with `sound`, and converts a tap back to `AttentionTarget`.
  `RootView` drains intents on change, on appear and on returning to the foreground, and passes the
  pending target to the shell.
- **Shell.** `PaseoShellView` now updates `AttentionCenter.focusedAgentId` from selection and scene
  phase (nil in the background), and consumes a tap target through the same `select(...)` path as
  the sidebar. Agent taps ignore the workspace hint. Terminal taps pick the newest agent in the
  terminal's workspace and open the workspace panel; there is no per-terminal page target in the
  panel API today, so the panel opens on whatever page it last showed.
- **Settings.** Settings → General → Notifications ("Agent notifications", default on) persists
  `paseo.notifications.enabled`; switching it on asks for OS permission. The footer states the
  local-only limit.

## Live check (sandbox, 2026-11-09)

Against the sandbox daemon (v0.15.2), using only `/tmp/fixture-sandbox` and the designated
fixture agent:

- `session.events.set_subscription.request` (the modern opt-in used by the reference app) is
  rejected by this daemon as `unknown_schema`, with or without the
  `explicit_event_subscriptions` capability. This client cannot opt into the modern event feed, and
  must keep decoding the legacy `agent_stream` attention event.
- With a live `fetch_agents_request` subscription (`subscribe`) plus a presence heartbeat, the
  sandbox agent's turn still ends in `turn_failed` with `[System Error] Free usage limit reached`
  (opencode free tier). No `finished`/`permission` transition could be produced, so no live
  attention event was observed; the daemon did not emit attention for the failed turn either. The
  event shape is covered by protocol tests built from the documented payload and the reference
  daemon's legacy branch, not by a captured live attention event.

## Gaps

- No true push while the app is closed (above); no relay, APNs or Expo token.
- Terminal tap routes to the workspace/panel, not to the terminal tab; the panel has no
  terminal-selection API.
- The local notification body for `finished` uses the daemon's copy when present. For legacy
  events without a `notification` object, this client falls back to the generic title/body; it
  does not reconstruct a preview from an unopened agent's timeline.
- No sound/test-notification preferences (the ticket asks for the toggle only).
