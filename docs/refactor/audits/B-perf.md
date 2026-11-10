# Audit B: SwiftUI performance (2026-11-10, HEAD 29d78eb)

A read-only audit run by an Explore agent and checked by the lead where cited in PLAN.md. Paths
are relative to `Packages/PaseoUI/Sources/PaseoUI/` unless they start with `App/` or `PaseoCore/`.
None of these timings were measured; everything comes from the code.

## New findings (not in `docs/perf/overall-perf.md`)

| # | Impact | Finding | Where |
|---|---|---|---|
| N1 | high | Every keystroke re-renders all of `ClaudeChatView`: the header, the transcript `ForEach`, every visible turn row (~10 fresh closures each) and the composer. `body` reads `store.draft` in several places: `slashQuery` / `mentionQuery` animation values, `DraftMetrics.isTall`, the send-control and `canSendMessage` trims, and `mentionMenu`. | `ChatComposer.swift:22-23,196,442`, `ChatSlashCommands.swift:20`, `ChatMentions.swift:26,68`, `ChatAttachments.swift:26`, `ChatTranscript.swift:112-133` |
| N2 | high | Each chat `body` evaluation does three full `timeline.rows` scans for the mascot `onChange`s, three `session.agents` passes, and a `boundaryBefore` `firstIndex` over all rows for every visible turn (turns × rows). `Array(store.turns.enumerated())` also copies the turns array on every evaluation. | `ChatMascot.swift:64-108`, `ClaudeChatView.swift:380-393`, `ChatTranscript.swift:106,150,475-478` |
| N3 | high | The diff rebuilds `DiffModel` **per row**, so rendering is quadratic: `lineRow` reads `model.totalWidth`, and `model` is a computed property. `anchoredDrafts` filters all drafts per row, and `snippet` builds both models. | `WorkspaceChangesDiffView.swift:41,85,640,668,798-863` |
| N4 | med-high | The file viewer works in `body`: an 8 MB base64 decode plus `UIImage(data:)`, a single `Text` holding the whole file with `.fixedSize` and `.textSelection`, the attributed-string conversion on every evaluation, and a non-lazy gutter of up to 4,000 `Text`s. | `WorkspaceFileViewer.swift:386-399,561,729-765` |
| N5 | medium | `RootView`'s `.onChange(of: session.attention.pending)` re-runs the root, which then rebuilds the shell and the sidebar. The shell `body` also reads `session.connection` and `agentsError`. | `App/Sources/RootView.swift:~111`, `PaseoShellView.swift:230,328` |
| N6 | medium | Every agent upsert re-sorts all agents, parsing a date in the comparator, and assigns `agents` even when nothing changed. Every unhandled event goes to about 7 handlers, each building its own `JSONDecoder`, and loops over every conversation twice. | `HostSession.swift:325-331,431-476`, `TerminalsStore.swift:471`, `HostSettingsStore.swift:472`, `GitExtras.swift:78`, `BackgroundWorkStore.swift:103`, `ConversationSubagents.swift:102` |
| N7 | medium | Image attach decodes, resizes to 2048 px and JPEG-encodes on the main actor. | `ComposerAttachments.swift:154-170`, `ChatAttachments.swift:39`, `DraftChatView.swift:577` |
| N8 | medium | The chat image loader decodes on the main actor and shares `checkout.files.read` state with the Files page, so concurrent images overwrite each other's results. **This is also a correctness bug.** | `ChatComposer.swift:649-661` |
| N9 | medium | Non-lazy file and commit lists in the Changes page; the overlay menu builds a button per file. | `WorkspaceChangesView.swift:147-170,1193` |
| N10 | low-med | A new formatter is created per row or per call. | `WorkspaceChangesView.swift:1240`, `WorkspaceFileFormat.swift:47`, `WorkspacePRPane.swift:500`, `ChatBackgroundWork.swift:183`, `ScheduleShared.swift:44,58`, `WorkspaceCommitDiffView.swift:23` |
| N11 | low-med | `ClaudeLoader` runs an uncapped `TimelineView(.animation)` + `Canvas` (120 Hz) inside the status line. The schedules list makes a network `load()` call every 5 s while it is open. | `ClaudeLoader.swift:41`, `ClaudeStatusLine.swift:169,178`, `SchedulesListPage.swift:17,35` |
| N12 | low | History search lowercases every title per keystroke; Diagnostics compiles 4 regexes per redaction. | `ClaudeHistoryView.swift:27-31`, `DiagnosticsPage.swift:218` |

## Open items from the overall-perf audit

- **E (diffs): still present.**
  - The diff model is computed.
  - `visibleRows` and `visibleSideRows` filter every row.
  - Both scroll views are non-lazy, with `.textSelection` over the whole container.
  - `diffScroll` returns an `AnyView`.
  - `ClaudeToolDetail.swift:39` parses in `body`, and `:126` is non-lazy.
  - `ClaudeFileCalls.swift:108-140` re-splits `diffStat`.
  - `ChatWorkGroup.swift:190` calls `WorkRow.merging` in `body`.
  - `WorkspaceCommitDiffView` is already lazy.
- **G (shell): still present.**
  - The shell `body` depends on `agents`, `workspaceDirectory`, `connection` and `agentsError`.
  - Two drawer drags sit on the conversation and one on the panel.
  - Every vertical scroll writes `@State directionDecided` once per attached drawer.
  - The `ConversationCard` dim and hairline re-render every frame and are inserted or removed at
    progress 0.
- **H (rich): still present.**
  - There is one `WKWebView` per card, and its `MutationObserver` has no throttle.
  - `contentHeight` is written on every message.
  - The document HTML is rebuilt in `body` and compared in full.
  - `LPLinkView` is still used, and the local image loader still runs on the main actor.
- **I (lists): still present.**
  - The history view groups and parses dates in `body`, with a `DateFormatter` per row.
  - In `CommandCenterView`:
    - `sections` is built twice per `body`;
    - the recents sort parses dates in its comparator;
    - `activityDate` scans every agent for each comparison, and `workspaceDot` once per row;
    - the query has no debounce.
  - Settings has no lazy stacks (low impact).
- **J (launch): still present, low impact.**
  - A synchronous Keychain read, the migration, the appearance JSON decode and the host refresh
    all run in `AppModel.init`.
  - The connect starts immediately.
