# Status and handoff

Last updated 2026-11-09. Read `ARCHITECTURE.md` and `AGENTS.md` first. All work is local on
branch `foundation`; nothing has been pushed, and `main` is untouched.

## Vision (agreed with the user)

The Claude iOS UI (claude-ios-ui, now `Packages/PaseoUI`) is the base. Enhancements come from
DSH Claude style (turn layout, status wording and timing, mascot behavior: specs in
`docs/research/06`). The Paseo daemon is the unmodified backend (`Packages/PaseoCore`). Everything
is wired coherently, new screens match the existing style, and the target is full parity with
Paseo's app/web client (desktop-only features flagged, not silently dropped). Reuse existing
wording and assets; don't invent quips. Never reuse `~/workspace/claude-ios-ui` (a failed attempt).

## Done and merged on `foundation`

- PaseoCore: protocol, `DaemonConnection` (reconnect, binary frames), `HostSession`,
  `ConversationStore` (live turns), `AgentControlStore` (permissions, create, pickers),
  `WorkspaceDirectory`/`CheckoutStore`/`WorkspaceFiles` (workspaces, git, diffs, files),
  `TerminalsStore` (terminals, scripts). 156 tests, run `swift test` in `Packages/PaseoCore`.
  `swift run paseo-probe --help` exercises everything live.
- Research specs `docs/research/01–07`, audited by DeepSeek (07 not audited).
- M1: ClaudeUI became `Packages/PaseoUI`, Claude-only screens deleted. The app builds in Xcode
  (user confirmed) but still shows the old generic screens until M2.
- M2 merged (816a491): ClaudeUI chat + shell on live data (`Chat/`), old generic screens deleted.
  Waiting on the user's Xcode build.
- Phase 3 backend merged (T9 schedules, T10 host settings/presence/slash commands, T11 git
  extras, T12 attachments/search/subagents, T13 rich detection + mascot state machine).
  386 tests green. Gap: T12 file byte upload needs binary send in PaseoKit.

## In flight (Paseo agents, each in its own worktree; branch = ticket)

| Ticket | Branch | Worker | What |
| --- | --- | --- | --- |
| M2 | `m2-claude-style-chat` | DeepSeek (pi) | ClaudeUI chat + shell on live data, DSH turn UX. Two commits: M2a conversation, M2b shell. |
| T9 | `t9-schedules` | DeepSeek | Schedules/heartbeats store |
| T10 | `t10-host-settings` | DeepSeek | Daemon config, heartbeat/presence, slash commands |
| T11 | `t11-git-extras` | DeepSeek | Modern diff pipeline, discard, branches, PR status, live files |
| T12 | `t12-attachments-search` | DeepSeek | Attachments, timeline search, subagents |
| T13 | `t13-rich-mascot-logic` | inkling (max) | Rich content detection + mascot state machine (pure logic) |

Tickets: `docs/tickets/`. Worktrees: `/home/paseo/.paseo/worktrees/0264elgj/<branch>`.

## How to land them

1. Review each diff (public API shape, sandbox hygiene, no UI in backend tickets).
2. Merge M2 first, then have the user build in Xcode (File → Packages → Reset Package Caches,
   Product → Clean Build Folder) and paste errors as text.
3. Backend tickets T9–T12 all touch `HostSession.swift`, `FakeDaemonClient.swift`,
   `paseo-probe/main.swift`: merge them one at a time, or give them to one integration agent
   (as done for phase 2: merge, keep all sides, routing `.unhandled` inside `.unhandled`).
   Always `rm -rf Packages/PaseoCore/.build` before judging a test failure: a stale incremental
   build once produced a fake failure.
4. After merging, `swift test` must be fully green.

## In flight (2026-11-09, ~07:30 UTC; user away from the Mac)

Merged on `foundation` and pushed, NOT yet built in Xcode by the user: M3a–e (right-edge
workspace panel: Agents/Files/Changes/Terminal via SwiftTerm, mention-in-chat, live file
updates), M4a settings, M4b schedules, M5a crab (+ Settings "Show mascot"), M5b rich content,
M8a (slash menu, presence, copy, bubble grow-in), M7 (title menu, find bar, History, bottom on
agent switch), M2.7 (add project/clone, full new-workspace, diff stats, Pinned section),
R9 `docs/PARITY.md` (the roadmap). Last user-built commit: dbad49b (M2.6b + underline fix).
When the user is back: pull, Reset Package Caches (SwiftTerm is new), build, paste errors.

Also merged since: T14 file upload, M7b chat-follow + permission cards, M8b queue/drafts/full-screen
composer, T15 git/file ops backend, M6a attachments, M7c file-call rows + summaries, M2.8 pin/rename/
archive undo (confirmation kept when the host lacks archiveUndo), M4c host settings, M3f panel git +
file ops, M2.9 sidebar badges/display options/hide, M8c provider features (Features page, Fast chip,
Settings default send steer/queue/interrupt), M3g terminal key bar, tab unread/rename/close, script
restart/view service, local links, 2k scrollback (PaseoCore 354/126/17 = 497 green; one-off
DaemonConnectionTests flake → T16). Unsure-compile hot spots: M3g SwiftTerm APIs (inputAccessoryView key
bar, linkReporting/requestOpenLink, changeScrollback), M8c nested Features pages in ClaudeAgentControlsSheet.

Running (inkling workers, reused per area; DeepSeek allowed outside weekday 01–04/06–10 UTC):
- M7d `m7d-anchor-reveal` on worker 0778f3b0: chat-anchor, reveal, rewind (transcript).
- T16 `t16-flake-usage` on worker 918fee9a: connection-test flake, context/usage store.
- R10 `r10-split` on worker 79dd09d6: split PaseoSidebar + ClaudeSchedulesView into files (pure move).
Known store gaps (from M7/M8a/M2.7): no unarchive-agent RPC (History shows active only);
commands cache never invalidated; GitHub search has no star count.
Next candidates: split ClaudeChatView (2.1k lines) once M7d lands; notifications/push research (DeepSeek after 10:00 UTC).
Roadmap order: see PARITY.md suggested milestones, renumbered below.

UX decisions so far: left drawer = navigation (projects → workspaces), right panel = inside the
workspace, the chat stays clean. Composer keeps the Claude iOS shape; turn UI follows DSH.

## Next (UI, decided by the lead, built by workers)

- M3: workspace surfaces in ClaudeUI style: file browser, Changes/diff view, terminals (SwiftTerm
  package), new-workspace flow (ClaudeCodeDraftView adapted), workspace tabs polish.
- M4: settings and hosts (ClaudeUI settings shell → Paseo host/app settings, T10 store), schedules
  UI (ClaudeRoutinesView → T9 store).
- M5: rich content rendering (T13 detection → LPLinkView, YouTube, images, SVG) and the mascot
  (T13 state machine). Mascot decided: the DSH crab (Clawd), personal app.
- Later: relay pairing (QR, E2E) for use away from the LAN; iPad layout.

## Working rules that matter

- Workers: DeepSeek via `pi/opencode-go/deepseek-v4.1-flash` (or `omp/...` mode `full`);
  inkling via `opencode/opencode/inkling-2-small-free`, mode `build`, thinking `max`.
  Tell them: no background tasks or subagents.
- One DeepSeek agent audits research instead of the lead re-checking it.
- SwiftUI can't compile on Linux: UI tickets must `rg` deleted types and `swiftc -parse`; the user
  builds in Xcode. Avoid Apple-only `#if` branches.
- No screenshots unless needed (quota).
