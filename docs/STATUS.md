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
  Waiting on the user's Xcode build. T9–T13 all finished; `integration-phase3` (DeepSeek) is
  merging them (worktree `/home/paseo/.paseo/worktrees/0264elgj/integration-phase3`).

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

## Next (UI, decided by the lead, built by workers)

- M3: workspace surfaces in ClaudeUI style: file browser, Changes/diff view, terminals (SwiftTerm
  package), new-workspace flow (ClaudeCodeDraftView adapted), workspace tabs polish.
- M4: settings and hosts (ClaudeUI settings shell → Paseo host/app settings, T10 store), schedules
  UI (ClaudeRoutinesView → T9 store).
- M5: rich content rendering (T13 detection → LPLinkView, YouTube, images, SVG) and the mascot
  (T13 state machine). **Open decision for the user:** our own mascot vs. the DSH crab (Anthropic's
  Clawd; not covered by the plugin's license; personal use is the user's call).
- Later: relay pairing (QR, E2E) for use away from the LAN; iPad layout.

## Working rules that matter

- Workers: DeepSeek via `pi/opencode-go/deepseek-v4.1-flash` (or `omp/...` mode `full`);
  inkling via `opencode/opencode/inkling-2-small-free`, mode `build`, thinking `max`.
  Tell them: no background tasks or subagents.
- One DeepSeek agent audits research instead of the lead re-checking it.
- SwiftUI can't compile on Linux: UI tickets must `rg` deleted types and `swiftc -parse`; the user
  builds in Xcode. Avoid Apple-only `#if` branches.
- No screenshots unless needed (quota).
