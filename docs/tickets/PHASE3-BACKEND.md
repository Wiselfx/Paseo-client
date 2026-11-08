# Phase 3 backend tickets (T9–T13)

Backend only: PaseoProtocol + PaseoStore + tests + probe. No SwiftUI, and don't touch
`Packages/PaseoUI` or `App/` (UI work is decided separately). Follow
`docs/tickets/PHASE2-CONVENTIONS.md` exactly (fixtures first, sandbox-only, tolerant decoding,
`@MainActor @Observable` stores, errors as observable properties, a probe subcommand).

Parallel tickets all edit `HostSession.swift`, `FakeDaemonClient.swift` and `paseo-probe/main.swift`.
Keep those edits to a few lines each (one stored property, one init line, one routing line, one
probe `case`), and put everything else in your own files, so merges stay trivial.

## T9: Schedules and heartbeats
Spec: `docs/research/04-protocol-agents-permissions-settings.md` (schedules/heartbeats sections),
and `docs/research/01-app-features.md` "Schedules". A `SchedulesStore`: list, inspect, create
(name, prompt, cron, timezone, max runs, provider/model/mode/thinking, project/workspace),
update, pause, resume, run once, logs, delete. Sandbox: create schedules with `maxRuns` and a
far-future or disabled cadence, prompts targeting `/tmp/fixture-sandbox`; delete them all at the end.

## T10: Host settings and session presence
Spec: doc 04 (daemon config, providers settings, client heartbeat, push registration, slash
commands, attention), doc 01 Settings sections. A `HostSettingsStore`: read the daemon config and
the subset the daemon allows to patch (respect `expectedRevision`), provider enable/disable if the
protocol has it, profiles list. Also: `client_heartbeat` every 15 s with `focusedAgentId` and app
visibility (an API the app calls when focus/visibility changes), and `list_commands_request`
for the slash-command menu per agent. Sandbox: read config freely; **write only a harmless value
and restore it immediately**, or skip writes if no harmless field exists (say so).

## T11: Git extras and live files
Spec: doc 02 §4.1 (modern binary `diff.subscribe.request`, gated by `features.diffSubscription`),
§5.6 discard changes, §5.8 branch suggestions and switch branch, §6.1 PR status, §7.2
`fs.file.subscribe.request`. Extend `CheckoutStore`/`WorkspaceFiles` in new files (extensions
or helper types), keeping their existing public API. Prefer the modern diff pipeline when the
feature flag is present, falling back to the existing legacy one. Sandbox: `/tmp/fixture-sandbox`
and `/tmp/fixture-git` only, local bare remotes only.

## T12: Attachments, search and subagents
Spec: doc 04 (attachments/uploads, images in `send_agent_message_request`, subagents/provider
subagents, timeline search `agent.timeline.search.request`). Extend `ConversationStore` through
new files: send with image/file attachments (upload flow if the protocol requires it), search
inside a conversation (returns locations to scroll to), and a subagents list for an agent.
Sandbox: the fixture-sandbox agent `1c51ee58-765c-4f8d-bf27-7009338b361e` or agents you create
there; archive yours at the end.

## T13: Rich content detection and mascot state (pure logic, no daemon)
Two pure, fully unit-tested modules in a new target-free folder `PaseoStore/Rich/`:
1. **Rich content detection** from `docs/research/05-rich-media-spec.md`: given assistant
   Markdown, return a list of blocks/annotations the UI will render (link card for standalone bare
   URLs, YouTube full/inline, bare image URLs, local image paths, raw SVG blocks, `visualize`
   fences). Encode every detection rule and edge case from the spec as tests (cite the spec
   section in each test name/comment). No networking: metadata fetching is the UI's job.
2. **Mascot state machine** from `docs/research/06-dsh-ux-spec.md` (mascot section): states,
   priority tiers, triggers mapped to *our* store signals (turn running/completed/failed, tool
   call kinds, subagents, compaction, permission/attention, idle time), minimum display times.
   Pure: input events with timestamps, output the current state. Test that a successful turn can
   never produce an error/failure state (a known bug in a previous attempt).
No probe needed for T13; tests are the deliverable.
