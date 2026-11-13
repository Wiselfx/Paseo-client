# Architecture

Paseo Client is a native iPhone app for the [Paseo](https://github.com/getpaseo/paseo) daemon.
The daemon runs your agents on your machine; this app is a window onto it that feels like a
messaging app. The daemon is the backend and we never change it. Everything here is client.

## Layers

```
App/                  Composition root: app entry, navigation, settings storage, Keychain.
                      Thin. Owns no logic a test would want.
Packages/PaseoUI      (Apple platforms only; one module, including the former ClaudeUI parts bin)
  Conversation/       The chat: Screen (header + controller), Transcript, Turn, Composer,
                      Sheets, Mascot, and Prose (Markdown + rich content).
  Workspace/          The panel: Agents, Files, Changes (diff, PR), Terminals.
  Sidebar/            The drawer's content: directory, rows, menus, Search (CommandCenter).
  Shell/              The container: ShellView (routing), ShellContainer (UIKit drawers),
                      ShellDrawer (the SwiftUI↔UIKit bridge), EdgeDrawer (geometry).
  Settings/ History/ Schedules/ Draft/ Voice/ Notifications/ Onboarding/ Pairing/
                      One folder per surface; each depends on PaseoStore + DesignSystem and
                      never on another surface. PaseoStore re-exports Kit/Protocol value
                      types for display; surfaces never create connections or send requests.
  DesignSystem/       Tokens (Palette, Typography, Metrics, Motion, SettingsKeys), haptics,
                      PaseoFormat, and Components/ — the shared views every surface uses
                      (ListRow, PageList, EmptyState, LoadingState, InlineBanner, Toast,
                      StatusDot, StatePill, DiffStat, SheetScaffold, ShellHeader, Buttons).
                      No Paseo types.
Packages/PaseoCore    (Foundation only: builds and tests on Linux)
  PaseoStore          @Observable state the UI reads, and the pure logic behind it:
                      TimelineState (merging deltas), TurnBuilder (grouping into turns).
  PaseoKit            One WebSocket to one daemon: hello, requests, events, reconnect.
  PaseoProtocol       Wire types. Mirrors packages/protocol/src/messages.ts upstream.
```

Dependencies point down only. SwiftPM targets enforce this: a wrong import fails to compile.

### Why the split at PaseoCore

Everything that talks to the daemon or decides what to show is plain Swift with Foundation and
Observation. That code builds and tests on Linux, next to a live daemon, so it can be verified
without a Mac. SwiftUI code can only be checked in Xcode, so it stays thin: views render store
state and send intents back. If a view needs an `if` about protocol details, the logic belongs in
the store.

## Talking to the daemon

- One `DaemonConnection` per host, behind the `DaemonClient` protocol (`PaseoKit/DaemonClient.swift`).
  The app reaches the daemon over LAN or Tailscale with the daemon password, or over the relay: an
  E2E-encrypted (Noise NK) channel with key pinning, paired by QR code or pasted link
  (`PaseoKit/Relay/`, `PaseoUI/Pairing/PairingFlow.swift`, `PaseoKit/SavedHost.swift`). The endpoint
  picks the path: `DaemonConnection.swift` wraps the base transport in the relay transport when the
  endpoint carries a relay link.
- Every frame is first decoded as an `InboundHeader` (outer type, message type, requestId). Responses
  go to the waiting request; everything else becomes a `DaemonEvent`. The full decode happens only
  where the type is known.
- **Forward compatibility.** The daemon updates on its own schedule. Every enum decodes unknown
  values into an `.unknown` case. Unknown fields are ignored. Never make a decoder throw on
  something a newer daemon might add.
- **Capabilities.** `ServerInfo.features` is checked in the store, once. Features read a plain flag.
- **Fixtures, not guesses.** `Tools/capture-fixtures.mjs` records real traffic. Protocol tests
  decode those files. When adding a message type, capture it first.
- Upstream reference: the protocol docs in getpaseo/paseo, especially `docs/timeline-sync.md`,
  `docs/protocol-compatibility.md` and `docs/agent-stream-disclosure.md`.

## The turn

The chat is not a list of messages. It's a list of **turns**, built by `TurnBuilder`:

```
Turn
├─ userMessage                     the bubble you sent
└─ segments
   ├─ work   "2 thoughts, 1 tool call"   consecutive reasoning + tool calls, collapsible
   ├─ prose  assistant markdown
   ├─ work   …
   └─ prose  final answer
phase: running · completed · failed     duration: "Completed in 4s"
```

Live updates arrive as small deltas. `TimelineState` merges them into rows that look exactly like
the daemon's projected history. Replaying the stream must equal the projection; a test checks
this. Rows have stable ids so views keep identity while text streams in.

## Rendering rich content

Assistant prose renders as Markdown. Rich content (link previews, images, maps, file cards, code)
comes from one registry in DesignSystem that maps detected content to a cell. Adding a new kind
of rich content means adding one entry there, never a special case inside a view.

## Feel

Haptics, motion and the "alive" status lines (the playful words while the agent works) live in
DesignSystem and are triggered by store state changes, not by individual views. That keeps the
feel consistent and lets one place tune it.

## Upstream first

Paseo upstream (getpaseo/paseo) is the specification. Before changing any function, feature,
behaviour or performance measure, find how upstream does it, match it, and cite it as
`Upstream: path:line`. If upstream does not have it, we do not build it. The rule is R-7 in
`AGENTS.md`; the full procedure is in `docs/tickets/_L-common.md`.

## Repo rules

- Work happens on branches in worktrees. `main` only gets reviewed merges.
- `ARCHITECTURE.md` is the map; tickets in `docs/tickets/` are the work orders.
- Don't add a dependency without a note in the PR saying why it beats writing it.
