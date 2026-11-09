# Parity checklist — Paseo app/web + DSH Claude-style vs this client

Branch `r9-parity`. What this is: one checklist of every user-facing feature of
(a) Paseo's own app/web client (`/home/paseo/dev/paseo-reference/packages/app/src`) and
(b) the DSH Claude-style plugin (`/home/paseo/dev/dsh-claude-style-reference`), with this
client's status for each. Docs only; no code changed.

How to read the rows:

- `Status:` is one of `done` (UI code exists in this client and is reachable from the app — or is the
  whole point of a wired screen) · `store only (no UI)` (the logic/store exists in PaseoCore; nothing
  user-facing renders it) · `in flight (M3a–d)` (ticket written, worktree exists, only contract stubs
  committed) · `missing` (neither) · `desktop-only (flag)` (exists in the reference as a desktop/web
  feature; flagged here so it is not silently dropped) · `not applicable (why)`.
- `M3 is in flight: panel, files, changes, terminal` — see `docs/tickets/M3-workspace-panel.md` and
  the worktrees under `/home/paseo/.paseo/worktrees/0264elgj/m3{a,b,c,d}-*`. They contain only the
  contract stubs from this branch's base commit (`4131a41`).
- `M2 merged`; turn UI on DSH live-observation was `M2.6b` (done). Stores from T1–T13 are merged on
  `foundation` (phase 2 + phase 3). None of T9–T13 stores is referenced by the UI yet
  (`rg` over `Packages/PaseoUI` and `App` for `schedules`, `hostSettings`, `terminals`, `gitExtras`
  returns nothing).
- Unwired ClaudeUI leftover screens (`ClaudeCode*.swift`, `ClaudeSettingsView.swift`,
  `ClaudeRoutinesView.swift`, `ClaudeUsageSettingsView.swift`, `ClaudeProjectsView.swift`, …) are dead
  code: they are not reachable from `App/`, predate the Paseo stores, and are never marked `done`
  below. Where one is a plausible M4 starting point, the row says so.

Scope notes:

- This client is iPhone-first and single-host (one daemon, direct connection). Anything multi-host is
  `missing` unless noted.
- "Reachable from the app" means: `App/Sources/RootView.swift` → `PaseoShellView` → `PaseoSidebar` /
  `ClaudeChatView` and their sheets. Connect → shell → chat is the whole wired surface today.
- Sources are cited per row: `docs/research/NN-…` docs carry the reference inventory with their own
  `path:line` citations; `"this client:"` cites our code. Line numbers in the docs are as of this
  branch.
- The turn-UI DSH rows are feature-level, not pixel-level. Known visual drift (palette details, sweep
  implementation) is tracked in `docs/research/08-dsh-live-observation.md` §5–§8; it does not change
  any status here.
- DSH rows about *reproducing the web host itself* (zoom plumbing, `::highlight` rewrites, layout
  services) are `not applicable`; rows about the *conversation experience* are the ones this client is
  actually chasing.

Status counts are in `## Counts` at the very bottom.

## Connection & hosts

- [ ] Feature: Direct connection screen (host / port / password) with inline failure states — Status: `done` — Source: this client `App/Sources/AppModel.swift:1`, `Packages/PaseoUI/Sources/PaseoUI/ConnectView.swift:1`; `docs/research/01-app-features.md:360`
- [ ] Feature: SSL toggle + Advanced connection URI on the direct-connection form — Status: `missing` — Source: `docs/research/01-app-features.md:360`
- [ ] Feature: Add-host flow with four methods (Direct / Remote SSH / Scan QR / Paste pairing link) — Status: `missing` — Source: `docs/research/01-app-features.md:360`
- [ ] Feature: Scan QR code pairing (native, encrypted relay) — Status: `missing` — Source: `docs/research/01-app-features.md:360`; plan: `docs/STATUS.md:72`
- [ ] Feature: Paste pairing link (`#offer=` validation, protected-offer password prompt) — Status: `missing` — Source: `docs/research/01-app-features.md:360`
- [ ] Feature: Host confirmation sheet ("Connect to this host?", fingerprint rows, changed-link variant) — Status: `missing` — Source: `docs/research/01-app-features.md:362`
- [ ] Feature: Pair a device — generate the pairing offer + QR/link from this host — Status: `missing` — Source: `docs/research/01-app-features.md:361`; protocol area `docs/research/04-protocol-agents-permissions-settings.md:1177` (no pairing-offer code exists in PaseoCore)
- [ ] Feature: Host picker / "Switch host" (sidebar footer + Settings) and "All hosts" filter — Status: `missing` — Source: `docs/research/01-app-features.md:363`
- [ ] Feature: Host chooser for deep-link flows (searchable) — Status: `missing` — Source: `docs/research/01-app-features.md:364`
- [ ] Feature: Relay / E2E-encrypted transport for use away from LAN — Status: `missing` — Source: this client: not implemented (LAN/direct only); plan: `docs/STATUS.md:72`
- [ ] Feature: Automatic reconnect with resync after drop (binary frames, backoff) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoKit/DaemonConnection.swift:1`, `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:58`; banner: `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatView.swift:229`
- [ ] Feature: Connection status banner in chat (reconnecting / failed) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatView.swift:229`
- [ ] Feature: Server info surface (hostname, server ID, connection state) in Settings sheet — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:611` (`ClaudeSidebarSettingsSheet` Host section)
- [ ] Feature: Disconnect from host — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:611`; `App/Sources/AppModel.swift:73`
- [ ] Feature: Host settings → Overview (rename host, color, sidebar badge, live preview) — Status: `missing` — Source: `docs/research/01-app-features.md:295`; settings redesign planned in `docs/STATUS.md:68` (M4)
- [ ] Feature: Host settings → Connections list (per-connection label, live latency, remove) — Status: `missing` — Source: `docs/research/01-app-features.md:297`
- [ ] Feature: Host settings → Danger zone (remove host / remove localhost connection) — Status: `missing` — Source: `docs/research/01-app-features.md:295`
- [ ] Feature: Host settings → Agents (Enable Paseo tools, browser tools, system prompt, orchestration skills, restart recovery, release idle agents) — Status: `missing` — Source: `docs/research/01-app-features.md:299`
- [ ] Feature: Host settings → Agent profiles (add/edit/delete/reorder, provider/model/mode/thinking/features, "when to use" notes) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:299`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:118`
- [ ] Feature: Host settings → Metadata (generation model: Automatic/Manual for titles, branch names, commit messages, PR drafts) — Status: `missing` — Source: `docs/research/01-app-features.md:300`
- [ ] Feature: Host settings → Workspaces (archive merged PR workspaces switch) — Status: `missing` — Source: `docs/research/01-app-features.md:302`
- [ ] Feature: Host settings → Providers (per-provider rows: status, model count, enable switch, remove; add-provider catalog with Install) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:303`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:99-117`, `Packages/PaseoCore/Sources/PaseoStore/AgentControlStore.swift:47`
- [ ] Feature: Host settings → Terminals (Enable terminal agent hooks, terminal profiles add/edit/reorder/delete) — Status: `missing` — Source: `docs/research/01-app-features.md:305`
- [ ] Feature: Host settings → Plugins (enable/disable, install from source, screens, logs, reload) — Status: `missing` — Source: `docs/research/01-app-features.md:306`
- [ ] Feature: Host settings → Pair device page (QR/link + Enable-relay upsell) — Status: `missing` — Source: `docs/research/01-app-features.md:298`
- [ ] Feature: Host settings → Projects page (per-host project list) — Status: `missing` — Source: `docs/research/01-app-features.md:296`
- [ ] Feature: Welcome screen (first run: connection method tiles) — Status: `missing` — Source: `docs/research/01-app-features.md:367`
- [ ] Feature: Onboarding flow (Appearance / Providers / Projects / Orchestration / Mobile steps, "Show setup again") — Status: `missing` — Source: `docs/research/01-app-features.md:368`
- [ ] Feature: Startup splash + managed-daemon failure/retry states — Status: `missing` — Source: `docs/research/01-app-features.md:415`
- [ ] Feature: Built-in daemon management (desktop: manage/keep-running/logs/restart, quitting overlay) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:366`
- [ ] Feature: Remote SSH connection method — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:360`
- [ ] Feature: Presence / client heartbeat for focus and open-agent awareness — Status: `done` — Source: docs/research/04-protocol-agents-permissions-settings.md:705-749; this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoShellView.swift` (`startPresence` on appear, `updateFocus` on selection change, `updateVisibility` on `scenePhase`, `stopPresence` on disappear); `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:162-225`

## Sidebar & navigation

- [ ] Feature: Drawer shell — edge-drag the content panel 1:1, spring settle, corner radius, dim, tap-to-close — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoShellView.swift:155-186`; `docs/research/01-app-features.md:100`
- [ ] Feature: Sidebar header — "New workspace" row — Status: `done` (footer pill, not header row) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:467` (footer pill; header is the wordmark only); `docs/research/01-app-features.md:99`
- [ ] Feature: Sidebar header rows History / Search / Schedules (configurable, reorderable/visibility in Settings) — Status: `missing` — Source: `docs/research/01-app-features.md:99`
- [ ] Feature: History nav row — Status: `missing` — Source: `docs/research/01-app-features.md:15`
- [ ] Feature: Schedules nav row — Status: `missing` (a non-functional "Scheduled" placeholder row opens a Coming-soon sheet) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:163-164`; `docs/research/01-app-features.md:16`
- [ ] Feature: Search nav row / command center — See Search & history section — Status: `missing` — Source: `docs/research/01-app-features.md:254`
- [ ] Feature: Footer Usage row (pinned-window summary meters) — Status: `missing` (no usage pipeline at all) — Source: `docs/research/01-app-features.md:100`; `docs/research/01-app-features.md:391-398`
- [ ] Feature: Projects grouped list, collapsible, ordered by newest activity — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:186-313`
- [ ] Feature: Workspace rows — title-or-branch, project/branch + relative-activity meta line — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:313-345`
- [ ] Feature: Status bucket dot on workspace rows (needs_input / failed / working / done / unseen) + unread attention dot — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:313-345,333,416-440`, `Chat/ClaudeChatComponents.swift:74` (`PaseoStatusDot`)
- [ ] Feature: Long-press workspace context menu (New agent here, Rename, Copy path, Copy branch name, Archive) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:313-342`
- [ ] Feature: Project context menu (New agent, Copy path, Remove project w/ confirmation) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:243-259`
- [ ] Feature: Project rename in sidebar — Status: `missing` (project rename RPC exists on the daemon; no store method, no UI) — Source: `docs/research/01-app-features.md:109`; docs/research/02-protocol-workspaces-git-files.md:61
- [ ] Feature: Remove project with confirmation — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:243-259`, `:115-131`
- [ ] Feature: Add project (folders / suggestions / new folder / GitHub clone) — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:125-147,248-300`; `docs/research/01-app-features.md:108`; `docs/research/02-protocol-workspaces-git-files.md:31-112`
- [ ] Feature: GitHub clone flow inside Add-project — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:248-300` (search + clone RPCs)
- [ ] Feature: Pinned workspaces ("Pinned" section, pin/unpin, shortcut) — Status: `missing` (no pin store, no UI) — Source: `docs/research/01-app-features.md:103`; `docs/research/02-protocol-workspaces-git-files.md:157`
- [ ] Feature: Display preferences popover (Sort Created/Manual/Last prompt; Grouping Project/Status/Labels; Title Title/Branch; Show Branch/Project/Host/PR/Checks/Services/Labels/Diff stats/Last activity; Checks style; Host/Project filters; background agents) — Status: `missing` — Source: `docs/research/01-app-features.md:104`
- [ ] Feature: Diff stats in sidebar meta line — Status: `missing` (descriptor carries `diffStat`; our meta line is `branch · age`) — Source: `docs/research/01-app-features.md:104`; this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:339-344`
- [ ] Feature: PR/MR badge on workspace rows + Checks rollup — Status: `missing` (PR badge exists on `GitExtrasStore`, never rendered — see Git & changes) — Source: `docs/research/01-app-features.md:102,161-163`
- [ ] Feature: Service (script) health in sidebar rows — Status: `missing` (TerminalsStore exposes script state; never rendered in the sidebar) — Source: `docs/research/01-app-features.md:102,236`
- [ ] Feature: Workspace labels (assign from menu/command center, filter sidebar by label) — Status: `missing` — Source: `docs/research/01-app-features.md:145`; docs/research/02-protocol-workspaces-git-files.md:181
- [ ] Feature: Host badge / per-host appearance in sidebar — Status: `missing` — Source: `docs/research/01-app-features.md:102`
- [ ] Feature: Host groups + "Switch host" picker in sidebar — Status: `missing` (single-host app) — Source: `docs/research/01-app-features.md:110`
- [ ] Feature: Archive workspace with running-agent warning + confirmation — Status: `done` (confirmation copy handles the running case) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:291-308,101-114`, `:469-475`
- [ ] Feature: Archive with Undo toast — Status: `missing` — Source: `docs/research/01-app-features.md:106`; docs/research/02-protocol-workspaces-git-files.md:147 (`workspaceArchiveUndo`)
- [ ] Feature: "Hide from sidebar" for workspaces — Status: `missing` — Source: `docs/research/01-app-features.md:105`
- [ ] Feature: Archive-undo global keyboard shortcut (desktop/wide layouts) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:411`
- [ ] Feature: Sidebar callouts (worktree setup discovery, plugin callouts) — Status: `missing` — Source: `docs/research/01-app-features.md:112`
- [ ] Feature: Help-and-support footer menu (Run diagnostics, Keyboard shortcuts, Report an issue, Discord, GitHub issue, What's new; community links) — Status: `missing` — Source: `docs/research/01-app-features.md:111,410`
- [ ] Feature: Attention rings on rows / tab chips (running, attention, failed) — Status: `done` (status dots; rings are a desktop treatment) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:313-412`; `docs/research/01-app-features.md:415`
- [ ] Feature: Help & community links on home (Star/Sponsor/Community) — Status: `missing` — Source: `docs/research/01-app-features.md:410`

## Workspaces & projects

- [ ] Feature: Agent tab chips in the workspace header (switch agents in place) — Status: `done` (M3a removes the row in favor of the clean header) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatView.swift:181` (`agentTabs`); ticket `docs/tickets/M3-workspace-panel.md:1(M3a)`
- [ ] Feature: Workspace screen with tabs (agents/terminals/files/diffs/PR/setup/browser), rename/close/pin/move — Status: `missing` — Source: `docs/research/01-app-features.md:116`; M3 delivers a right-side panel instead of tabs (`docs/tickets/M3-workspace-panel.md:M3a`)
- [ ] Feature: Right-side workspace panel (agents/files/changes/terminal pages, drag from edge) — Status: `in flight (M3a)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3a`; stubs `Packages/PaseoUI/Sources/PaseoUI/Workspace/` (15–16 lines each, `Text("…")` placeholders)
- [ ] Feature: New-workspace flow — minimal (project picker, optional name, creates worktree off base ref, create button) — Status: `done` (worktree-only; no isolation choice) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:761-880`
- [ ] Feature: New-workspace flow — full (project/host pickers, suggestions, Isolation Local vs New worktree, Branch/Start-from picker incl. PR checkout, optional title, launch target Chat vs Terminal, Manage profiles, Create) — Status: `missing` — Source: `docs/research/01-app-features.md:131`; docs/research/02-protocol-workspaces-git-files.md:125 (`workspace.create.request`)
- [ ] Feature: Worktree creation ("New worktree" isolation, branch-off, setup scripts run) — Status: `done` (branch-off from the minimal sheet; no PR checkout, no setup visibility) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:761-880`; docs/research/02-protocol-workspaces-git-files.md:185
- [ ] Feature: Workspace setup observation (setup status/subscribe, setup tab, "Run setup" rerun) — Status: `missing` — Source: `docs/research/01-app-features.md:125`; docs/research/02-protocol-workspaces-git-files.md:169
- [ ] Feature: Workspace setup dialog / callout ("Set up worktree scripts") — Status: `missing` — Source: `docs/research/01-app-features.md:132`
- [ ] Feature: Local (non-worktree) isolation for new workspaces — Status: `missing` — Source: `docs/research/01-app-features.md:131`
- [ ] Feature: Sessions / History screen (all sessions across workspaces/hosts, date groups, search, Load more, archived badge) — Status: `missing` — Source: `docs/research/01-app-features.md:135-137`
- [ ] Feature: Per-agent import from another tool ("Import session") — Status: `missing` — Source: `docs/research/01-app-features.md:126,412`
- [ ] Feature: Projects list per host (Settings → host → Projects) — Status: `missing` — Source: `docs/research/01-app-features.md:139,296`
- [ ] Feature: Project settings (Name, Icon; Worktree Setup/Teardown hooks; Scripts; Metadata generation prompts; stale paseo.json reload) — Status: `missing` — Source: `docs/research/01-app-features.md:141`; protocol `docs/research/04-protocol-agents-permissions-settings.md:1142`
- [ ] Feature: Project icon get/set (upload bytes) — Status: `missing` — Source: `docs/research/02-protocol-workspaces-git-files.md:83` (protocol implemented daemon-side; no store methods in PaseoCore)
- [ ] Feature: Project rename (custom name) — Status: `missing` — Source: `docs/research/01-app-features.md:141`; docs/research/02-protocol-workspaces-git-files.md:61
- [ ] Feature: Remove project — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:115-131`; `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:225-247`
- [ ] Feature: Rename workspace — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:329-331` (context menu) and `:101-114` (alert); `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:180-203`
- [ ] Feature: Workspace directory (projects → workspaces, live `workspace_update` subscribe, paged fetch, archived excluded) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:76-147`; fixtures-tested `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/workspaces/`
- [ ] Feature: Archive workspace (stops agents/terminals, removes from directory) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:204-224`, `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:100-114`
- [ ] Feature: Worktree archive with dirty/ahead warning and unpushed/uncommitted counts — Status: `missing` (plain confirmation only) — Source: `docs/research/01-app-features.md:177`; docs/research/02-protocol-workspaces-git-files.md:216
- [ ] Feature: Archive merged-PR workspaces automatically (project/workspaces setting) — Status: `missing` — Source: `docs/research/01-app-features.md:302`
- [ ] Feature: Workspace labels — See Sidebar & navigation — Status: `missing` — Source: `docs/research/01-app-features.md:145`; `docs/research/02-protocol-workspaces-git-files.md:181`
- [ ] Feature: Open-project flow ("Open folder" on host) — Status: `missing` (superseded by Add-project) — Source: `docs/research/02-protocol-workspaces-git-files.md:137`
- [ ] Feature: Workspace deck retention (recent workspaces stay mounted; instant switching) — Status: `not applicable (native navigation; `HostSession` keeps one `ConversationStore` per open agent in memory instead)` — Source: `docs/research/01-app-features.md:95,127`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:81-98`
- [ ] Feature: Workspace status descriptor piped into UI (needs_input/failed/running/done) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift` + `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:416-440`

## Conversation & turns

- [ ] Feature: Streaming timeline merged into turns (deltas → rows, replay == projection) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/TimelineState.swift:1`, `Turn.swift:1`, `Packages/PaseoCore/Tests/` (T2/T3 suites); `ARCHITECTURE.md:55-71`; reference `docs/research/01-app-features.md:39`
- [ ] Feature: Turn layout — user bubble → work group(s) → prose answer, phase running/completed/failed, "Completed in Ns" duration — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatView.swift` (`ClaudeTurnView`, `DurationText`); `docs/research/06-dsh-ux-spec.md:23-45`
- [ ] Feature: DSH turn UX — counted work header ("{n} thoughts, {n} tool calls"), roll-in digits — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeChatView.swift` (`ClaudeWorkGroupCell`, `ClaudeRollingNumber`); `docs/research/06-dsh-ux-spec.md:45-56`, `08-dsh-live-observation.md:72-103`
- [ ] Feature: DSH turn UX — process rows (36 pt thought/file rows, 24 pt shell rows, trailing chevron, 4 px gap, 0.5 px dividers) — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`ClaudeStepRow`, `rows`), `…/Chat/ClaudeChatComponents.swift` (`ClaudeDivider`), `…/Chat/ClaudeStyle.swift` (`tertiaryInk`, `divider`); `docs/research/08-dsh-live-observation.md:44-174`
- [ ] Feature: DSH turn UX — running turns fold by default, newest group open, thought rows expand while streaming — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`opensByDefault`, `isLive`); `docs/research/06-dsh-ux-spec.md:35-43`
- [ ] Feature: DSH turn UX — live waiting line ("Thinking…", file names, command descriptions, reasoning clauses, 1 s wording lock, 250 ms tick, 10 s "No response yet" overtime badge, turn clock) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeStatusLine.swift`, `ClaudeReasoningClause.swift`, `ClaudeLoader.swift`; `docs/research/08-dsh-live-observation.md:331-425`
- [ ] Feature: DSH turn UX — loader dots (three lanes rotating every 10 s, 480 ms morph, accent `#D97757`) — Status: `done` (Canvas renderer, bounce/line/orbit lanes) — Source: this client `…/Chat/ClaudeLoader.swift:1-248`; `docs/research/08-dsh-live-observation.md:212-330`
- [ ] Feature: DSH turn UX — highlight sweep across the status line (steps(48), ink band, 1.5 s) — Status: `done` (approximate: `TimelineView` mask rather than glyph-copy band; see doc 08 §3.4) — Source: this client `…/Chat/ClaudeChatView.swift` (`ClaudeSweep`), `…/Chat/ClaudeStatusLine.swift` (`ClaudeSweepText`); `docs/research/08-dsh-live-observation.md:394-425`
- [ ] Feature: DSH turn UX — serif prose (14/23), serif headings, palette links, 0.5 px rules — Status: `done` — Source: this client `…/Chat/ClaudeChatComponents.swift` (`ClaudeProse`), `…/Chat/ClaudeStyle.swift` (`proseLink`, `primaryInk`, `codeSurface`), `Packages/PaseoUI/Sources/PaseoUI/ClaudeMarkdownView.swift`; `docs/research/08-dsh-live-observation.md:564-606`
- [ ] Feature: DSH turn UX — user bubble #F4F2F3 / translucent dark, right-aligned — Status: `done` — Source: this client `…/Chat/ClaudeChatComponents.swift` (`ClaudeUserBubble`), `…/Chat/ClaudeStyle.swift` (`userBubble`); `docs/research/08-dsh-live-observation.md:304,524`
- [ ] Feature: DSH turn UX — drawn caret (2 px accent, 80 ms glide, 1 s step-end blink) — Status: `missing` — Source: `docs/research/08-dsh-live-observation.md:468-507`
- [x] Feature: DSH turn UX — chat-follow "back to the end" button pinned above the composer — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`backToEnd`, `onScrollGeometryChange`, `transcriptFade`); `docs/research/06-dsh-ux-spec.md:292-295`
- [ ] Feature: DSH turn UX — answer anchored to the top of the conversation when generation begins — Status: `missing` — Source: `docs/research/06-dsh-ux-spec.md` (feature `chat-anchor`), folder `dsh-claude-style-reference/packages/client/src/features/chat-anchor/`
- [ ] Feature: DSH turn UX — new-text reveal (per-character fade-in on arriving prose) — Status: `missing` — Source: folder `dsh-claude-style-reference/packages/client/src/features/chat-reveal/`
- [ ] Feature: DSH message actions — Retract / Edit / Rerun / Delete turn (opens a new session) — Status: `missing` — Source: `docs/research/06-dsh-ux-spec.md:81-85` (folder `message-actions/`)
- [ ] Feature: DSH chat-send — message bubble enters ("grow in place" or "fly up from the composer") — Status: `done` (grow-in-place variant: scale 0.96 + fade, 200 ms `cubic-bezier(0.22, 1, 0.36, 1)`; Reduce Motion fades; sent-this-session messages only) — Source: folder `dsh-claude-style-reference/packages/client/src/features/chat-send/`; this client `…/Chat/ClaudeChatComponents.swift` (`ClaudeUserBubble`)
- [ ] Feature: DSH chat-files — file-call rows (Read/Edit/Write) with verb-dot-filename, dotted underline link, merged per file, diff stats — Status: `missing` (reads/edits render as generic tool rows without file-name links or merging) — Source: this client `…/Chat/ClaudeToolDetail.swift` (`case .read/.edit/.write`); `docs/research/08-dsh-live-observation.md:133-160`; folder `chat-files/`
- [ ] Feature: DSH question-card — model question card restyled, moved to end of conversation — Status: `missing` — Source: folder `dsh-claude-style-reference/packages/client/src/features/question-card/`
- [ ] Feature: Copy response on a completed assistant turn — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift:525-631` (`ClaudeTurnView`)
- [ ] Feature: Copy per message (user and assistant) — Status: `done` (user bubbles: long-press → Copy; assistant prose: per-reply Copy response button, copies the turn's markdown) — Source: `docs/research/01-app-features.md:43`; this client `…/Chat/ClaudeChatComponents.swift` (`ClaudeUserBubble`), `…/Chat/ClaudeChatView.swift`
- [ ] Feature: "Worked for {{duration}}" completed-turn footer label — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`DurationText.completed`, `header` on `.completed`); `docs/research/01-app-features.md:45`, `docs/research/06-dsh-ux-spec.md:30`
- [ ] Feature: In-flight turn shows an elapsed clock + loader — Status: `done` — Source: this client `…/Chat/ClaudeStatusLine.swift` (turn clock); `docs/research/01-app-features.md:45`
- [ ] Feature: Fork chat from here ("Fork in a new tab" / "Fork in a new workspace", hidden on provider-subagent panes) — Status: `missing` — Source: `docs/research/01-app-features.md:44`
- [ ] Feature: Rewind to this message (conversation / files / both, with can't-undo warning) — Status: `missing` — Source: `docs/research/01-app-features.md:58`; docs/research/04-protocol-agents-permissions-settings.md:468
- [ ] Feature: Queue message (client-side queue until the turn ends; queued rows: Edit / Send now) — Status: `missing` (sending while running steers instead) — Source: `docs/research/01-app-features.md:46`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:406-434` (`activeTurnBehavior: "steer"`)
- [ ] Feature: Send and interrupt (follow-up admitted by interrupting the turn) — Status: `missing` — Source: `docs/research/01-app-features.md:47`
- [ ] Feature: Interrupt the running turn (square stop button / Escape) — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`composer.stop`, `store.cancel()`); `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:434-453`
- [ ] Feature: Slash commands (`/exit`, `/clear` + provider commands and skills in the composer `/` menu) — Status: `done` (menu above the composer card: name in Mono, argument hint, description, skill sparkle, filter as you type, max ~6 rows with scroll; spinner row while loading; hidden when the agent has none; placeholder "Type / for commands" then) — Source: `docs/research/01-app-features.md:62-63`; this client `…/Chat/ClaudeChatView.swift` (`slashMenu`); `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:128-160`
- [ ] Feature: Subagents track (pill: N subagents / N working / N failed / N needs input; panel with Detach/Archive/Archive finished; "Back to parent") — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:52`; this client `Packages/PaseoCore/Sources/PaseoStore/ConversationSubagents.swift`, `ConversationExtras.swift:68`; docs/research/04-protocol-agents-permissions-settings.md:980
- [ ] Feature: Tasks track (pill above composer: {{completed}}/{{total}} tasks) — Status: `done` (inline card, not the pill/panel) — Source: this client `…/Chat/ClaudeChatView.swift` (`ClaudeTodoCard` on `.todo` segment); `docs/research/01-app-features.md:53`
- [ ] Feature: Tool calls — collapsible rows with Input/Output expansion and an Error state; error output in mono red — Status: `done` — Source: this client `…/Chat/ClaudeStepRow`, `ClaudeToolCallDetail.swift` (`.failed` branch); `docs/research/01-app-features.md:54`
- [ ] Feature: Tool calls grouped as "edited N files / ran N commands / read N files" — Status: `missing` (per-call rows only) — Source: `docs/research/01-app-features.md:54`
- [ ] Feature: Turn collapse levels (Show more/less, View turn details, "Sent by {{name}}") — Status: `missing` — Source: `docs/research/01-app-features.md:55`
- [ ] Feature: Chat display setting (Full / Collapse tool calls / Collapse turns) — Status: `missing` — Source: `docs/research/01-app-features.md:55,275`
- [ ] Feature: Chat outline rail (jump between prompts, wide screens) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:56`
- [ ] Feature: Find in pane (Cmd/Ctrl+F, previous/next match, replace for files) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:57`
- [ ] Feature: Context window meter + details sheet ({{percentage}}% used, tokens, session cost, usage card) — Status: `missing` (an unwired ClaudeUI `ClaudeCodeContextSheet` exists; no store) — Source: `docs/research/01-app-features.md:59`; folder `context-stats/`
- [ ] Feature: Empty state ("Start chatting with this agent…") — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (empty content + `ClaudeHomeHero`); `docs/research/01-app-features.md:60`
- [ ] Feature: Archived agent callout with Unarchive — Status: `store only (no UI)` (agent archive RPC wired; no unarchive/callout) — Source: `docs/research/01-app-features.md:61,65`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:489-501`
- [ ] Feature: Agent stream resilience ("Couldn't load agent history", "This message was capped", load-older, archived callouts) — Status: `done` (Load-older row + inline errors; no archived callout) — Source: this client `…/Chat/ClaudeChatView.swift` (`olderHistoryRow`, error paths); `docs/research/01-app-features.md:61`
- [ ] Feature: Background work surface (background shells/monitors reported by provider) — Status: `missing` — Source: `docs/research/01-app-features.md:64`; docs/research/04-protocol-agents-permissions-settings.md:1033
- [ ] Feature: Live Markdown rendering of streamed assistant prose (lists, tables, blockquotes, headings, HR) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeMarkdownView.swift`, `MarkdownDocumentModel.swift`, `MarkdownTableMetrics.swift`; `docs/research/08-dsh-live-observation.md:564-606`

## Composer

- [ ] Feature: Text input with placeholder ("Message the agent…") — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift:358-380`; `docs/research/01-app-features.md:74`
- [ ] Feature: Send button (Enter / tap), disabled while empty — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`composer.send`); `docs/research/01-app-features.md:75`
- [ ] Feature: Send and steer when the agent is running (auto behavior) — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (send while running steers; label "Send and steer"); `docs/research/01-app-features.md:47,75`
- [ ] Feature: Long-press to queue / queue lane with Edit and Send now — Status: `missing` — Source: `docs/research/01-app-features.md:46,75,88-89`
- [ ] Feature: Interrupt (stop) control — See Conversation & turns — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`composer.stop`, `store.cancel()`); `docs/research/01-app-features.md:48`
- [ ] Feature: Keyboard behavior setting (Enter vs ⌘/Ctrl+Enter; Default send: Interrupt/Steer/Queue) — Status: `missing` — Source: `docs/research/01-app-features.md:75,272`
- [ ] Feature: Fullscreen input expansion — Status: `missing` — Source: `docs/research/01-app-features.md:77`
- [ ] Feature: Attachment tray (pills above the input) — Status: `missing` — Source: `docs/research/01-app-features.md:78`
- [ ] Feature: Add attachment menu (image / file upload / issue-or-PR; paste; drag-and-drop; large pasted text becomes a file) — Status: `missing` — Source: `docs/research/01-app-features.md:79-83`; docs/research/04-protocol-agents-permissions-settings.md:918
- [ ] Feature: Send message with attachments (image inline base64; file upload via `file.upload.request`) — Status: `store only (no UI)` (binary upload itself needs a PaseoKit binary-send that does not exist yet — T12 gap) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/ConversationExtras.swift:14-68`; `docs/STATUS.md:29`; docs/research/04-protocol-agents-permissions-settings.md:957
- [ ] Feature: Forge issue/PR attach + searchable picker — Status: `missing` — Source: `docs/research/01-app-features.md:79,83`; docs/research/02-protocol-workspaces-git-files.md:420
- [ ] Feature: Attachment actions (open/remove per pill, open in side pane) — Status: `missing` — Source: `docs/research/01-app-features.md:82`
- [ ] Feature: Agent controls (provider/model/thinking/mode) in the composer — Status: `done` (sheet, not chips) — Source: this client `…/Chat/ClaudeChatView.swift` (`composer.model` → `ClaudeAgentControlsSheet`); `docs/research/01-app-features.md:84`
- [ ] Feature: Provider-feature chips / aggregated Features sheet in composer — Status: `missing` — Source: `docs/research/01-app-features.md:84`; docs/research/04-protocol-agents-permissions-settings.md:308-342
- [ ] Feature: Agent profiles picker (fills provider/model/mode/thinking/features once at creation) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:85`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:118-127`
- [ ] Feature: Fast mode toggle in composer/command center — Status: `missing` — Source: `docs/research/01-app-features.md:325`
- [ ] Feature: Dictation mic button — Status: `missing` (the mic button exists but only focuses the field — it is not dictation) — Source: this client `…/Chat/ClaudeChatView.swift` (`roundButton("mic"…)`), `docs/research/01-app-features.md:86`
- [ ] Feature: Voice mode button — See Voice — Status: `missing` — Source: `docs/research/01-app-features.md:349`
- [ ] Feature: Drafts (persisted, restorable; forked into new agent) — Status: `missing` (in-memory `draft` per `ConversationStore`; lost on relaunch) — Source: `docs/research/01-app-features.md:87`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:338`
- [ ] Feature: @-files and /commands autocomplete popovers — Status: `missing` — Source: `docs/research/01-app-features.md:89`
- [ ] Feature: Composer visual parity — DSH conversation bar (14 px radius bar, hairline, shadow, flat toolbar; not the 18 px hero card) — Status: `missing` (ours is a 27 pt capsule, filled circle send, no drawn caret) — Source: `docs/research/08-dsh-live-observation.md:427-507`; this client `…/Chat/ClaudeChatView.swift:352-452`
- [ ] Feature: Caret animation (2 px accent caret, 80 ms glide) — See Conversation & turns / DSH turn UX — Status: `missing` — Source: `docs/research/08-dsh-live-observation.md:468-507`
- [ ] Feature: Composer placeholder reads "Type / for commands" (DSH conversation) — Status: `missing` (ours: "Message the agent…") — Source: `docs/research/08-dsh-live-observation.md:443`; this client `…/Chat/ClaudeChatView.swift:363`
- [x] Feature: Scroll-to-bottom fade bar + 40 px fade band (DSH) — Status: `done` (transcript fade to canvas; `allowsHitTesting(false)`) — Source: this client `…/Chat/ClaudeChatView.swift` (`transcriptFade`); `docs/research/06-dsh-ux-spec.md:288,294`
- [ ] Feature: Stop control as bare ring+square glyph while running (DSH) — Status: `done` (stop.fill circle; style drift tolerated) — Source: this client `…/Chat/ClaudeChatView.swift` (`composer.stop`); `docs/research/08-dsh-live-observation.md:450`

## Agents & models

- [ ] Feature: Provider catalogue load with loading/ready/error states, incremental snapshot pushes — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/AgentControlStore.swift:47-108,168-209`; `docs/research/04-protocol-agents-permissions-settings.md:813-889`
- [ ] Feature: New-agent sheet (provider/model/thinking/mode picker + initial prompt, creating state, error row) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeNewAgentSheet.swift:1-430`
- [ ] Feature: Model picker (searchable list, provider default, current model marked) — Status: `done` — Source: this client `…/Chat/ClaudeAgentControlsSheet.swift` (models page), `…/Chat/ClaudeNewAgentSheet.swift`; `docs/research/01-app-features.md:319`
- [ ] Feature: Thinking (effort) picker — Status: `done` — Source: this client `…/Chat/ClaudeAgentControlsSheet.swift` (thinking page); `docs/research/01-app-features.md:319`
- [ ] Feature: Mode (permission/access) picker — Status: `done` — Source: this client `…/Chat/ClaudeAgentControlsSheet.swift` (modes page); `docs/research/01-app-features.md:324`
- [ ] Feature: Switch model/thinking/mode on a running agent — Status: `done` — Source: this client `…/Chat/ClaudeAgentControlsSheet.swift` → `ConversationStore.setModel/setThinking/setMode`; `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:464-480`
- [ ] Feature: Per-agent changes apply through `agent.config.apply` bundle semantics — Status: `missing` (individual RPCs only; fine) — Source: protocol `docs/research/04-protocol-agents-permissions-settings.md:321`
- [ ] Feature: Provider enable/disable on the host (settings) — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:104-117`; `docs/research/01-app-features.md:303`
- [ ] Feature: Provider diagnostic sheet (diagnostic text, discovered models add/remove, custom model add, refresh) — Status: `missing` — Source: `docs/research/01-app-features.md:318`; docs/research/04-protocol-agents-permissions-settings.md:867
- [ ] Feature: Add custom model (Model ID input) — Status: `missing` — Source: `docs/research/01-app-features.md:318`
- [ ] Feature: Custom providers via host config (docs-only surface) — Status: `missing` (documented daemon config; no client work needed) — Source: `docs/research/01-app-features.md:323`
- [ ] Feature: Add-provider catalog with Install buttons — Status: `missing` — Source: `docs/research/01-app-features.md:317`
- [ ] Feature: Metadata generation model setting — See Connection & hosts (host settings) — Status: `missing` — Source: `docs/research/01-app-features.md:300`
- [ ] Feature: Agent profiles (list/add/edit/reorder/delete; applied once at creation) — Status: `store only (no UI)` (list/profiles read from daemon config; creation consumes them nowhere yet) — Source: `docs/research/01-app-features.md:320-321`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:118-127`
- [ ] Feature: Agent archive (with running-agent confirmation copy) — Status: `store only (no UI)` (archive wired; confirmation is sidebar-only for workspaces) — Source: `docs/research/01-app-features.md:65`; this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:489-501`
- [ ] Feature: Unarchive agent — Status: `missing` — Source: `docs/research/01-app-features.md:61`
- [ ] Feature: Agent rename — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:481-488`; `docs/research/01-app-features.md:116`
- [ ] Feature: Agent hard delete — Status: `missing` — Source: docs/research/04-protocol-agents-permissions-settings.md:361
- [ ] Feature: Detach provider subagent from parent's track — Status: `store only (no UI)` (detach RPC mapped) — Source: docs/research/04-protocol-agents-permissions-settings.md:451; this client `Packages/PaseoProtocol/Agents.swift`; no UI
- [ ] Feature: Provider subagent list/timeline (background tasks the provider reports) — Status: `store only (no UI)` — Source: this client `Packages/PaseoProtocol/Subagents.swift`, `Packages/PaseoStore/ConversationSubagents.swift`
- [ ] Feature: Fast mode (per-provider, composer + command center) — Status: `missing` — Source: `docs/research/01-app-features.md:325`
- [ ] Feature: Model switch no-op bug fix (M2.5a) — Status: `done` — Source: `docs/STATUS.md:58`, `git log` `325b984`
- [x] Feature: Agent list / history surface — See Search & history — Status: `done` (History screen, active agents only; archived hidden: `HostSession` discards them at ingest, no unarchive RPC) — Source: this client `Chat/ClaudeHistoryView.swift`; `docs/research/01-app-features.md:66`
- [ ] Feature: Attention flags on agents (permission/error/finished) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:321-360`; `docs/research/04-protocol-agents-permissions-settings.md:642`
- [ ] Feature: Agent snapshot cards re-render on `agent_update` (live title/model/status) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:124-180`; fixtures `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/agents/`

## Permissions

- [ ] Feature: Inline permission card in the timeline (title, kind symbol, description, Input/Output detail block) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudePermissionCard.swift`; `docs/research/01-app-features.md:49`
- [ ] Feature: Accept / Deny actions (danger-styled Deny; provider-offered actions honored verbatim) — Status: `done` — Source: this client `…/Chat/ClaudePermissionCard.swift`; `docs/research/01-app-features.md:49,331`
- [ ] Feature: Plan requests render as plan ("Plan" title, Implement/Accept) — Status: `done` (title + kind symbol; no separate Implement-only button logic beyond actions) — Source: this client `…/Chat/ClaudePermissionCard.swift` (`isPlan`, `.plan`); `docs/research/01-app-features.md:49,51,331`
- [x] Feature: Answered plan/permission state collapses to "Approved plan" / "Rejected plan" / "Canceled plan" — Status: `done` (client-side record of this session's answers, one quiet line in-place; the store drops resolved requests without remembering) — Source: this client `Chat/ClaudePermissionCard.swift`, `Chat/ClaudeChatView.swift`; `docs/research/01-app-features.md:49,331`
- [x] Feature: Question-kind requests render the question form ("How would you like to proceed?", per-question options + free-text other) — Status: `done` (Pi `ask_user` payload parsed from `request.input.questions`; fallback to generic card when unparseable) — Source: this client `Chat/ClaudePermissionCard.swift`; `docs/research/01-app-features.md:50`; `Packages/PaseoProtocol/Permissions.swift:13-27`
- [x] Feature: Plan card (standalone "Proposed plan" card with approve/reject) — Status: `done` (plan text from `metadata.planText` / `input.plan`, serif body, Approve / Reject) — Source: this client `Chat/ClaudePermissionCard.swift`; `docs/research/01-app-features.md:51`
- [ ] Feature: Permission resolution flows back through `agent_permission_resolved` (card disappears, no optimistic UI) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/AgentControlStore.swift:142-166`, `HostSession.swift` (permission events); `docs/research/04-protocol-agents-permissions-settings.md:572-641`
- [ ] Feature: Pending permissions survive restart/resubscribe (snapshots carry `pendingPermissions`) — Status: `done` — Source: docs/research/04-protocol-agents-permissions-settings.md:617; this client stores pending list on the conversation; fixtures `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/permissions/`
- [ ] Feature: OS permissions surfaces (iOS: none required today — no mic/camera use; desktop-only elsewhere) — Status: `desktop-only (flag)` (desktop: Microphone row in Settings → Permissions) — Source: `docs/research/01-app-features.md:332`
- [ ] Feature: Notification permission requested at startup (desktop) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:333`

## Files

- [ ] Feature: Workspace files store (list/read/entries, 512 KB max-read, binary-safe serialize) — Status: `done` (store; no UI) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/WorkspaceFiles.swift:13-110`; docs/research/02-protocol-workspaces-git-files.md:480
- [ ] Feature: File browser page in the workspace panel (directory rows, navigation, pull-to-refresh, error/empty states) — Status: `in flight (M3b)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3b`; stub `Packages/PaseoUI/Sources/PaseoUI/Workspace/WorkspaceFilesView.swift`
- [ ] Feature: File viewer (syntax-highlighted code in Mono, line numbers, horizontal scroll, copy; images; calm binary/too-large message) — Status: `in flight (M3b)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3b`
- [ ] Feature: Sort file list (Name / Modified / Size) — Status: `in flight (M3b)` (display of size/modified; cycle control not specified) — Source: ticket `docs/tickets/M3-workspace-panel.md:M3b`; reference `docs/research/01-app-features.md:199`
- [ ] Feature: Show/hide hidden files toggle — Status: `missing` — Source: `docs/research/01-app-features.md:200`
- [ ] Feature: New file / new folder (inline name input) — Status: `missing` — Source: `docs/research/01-app-features.md:201`; docs/research/02-protocol-workspaces-git-files.md:482
- [ ] Feature: File row context menu — Copy path / Copy relative path / "Mention in chat" (`@relative/path`) — Status: `in flight (M3b)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3b`; reference `docs/research/01-app-features.md:202`
- [ ] Feature: File row context menu — Open / Open to the side / Reveal / Download / Add to chat / Rename / Duplicate / Delete (with confirmation) — Status: `missing` — Source: `docs/research/01-app-features.md:202`; docs/research/02-protocol-workspaces-git-files.md:482
- [ ] Feature: File download through daemon token (progress toast; "Download complete/failed") — Status: `missing` — Source: `docs/research/01-app-features.md:210,405`
- [ ] Feature: Drag a file row into the composer (attaches as workspace-file attachment, line ranges) — Status: `missing` — Source: `docs/research/01-app-features.md:203`
- [ ] Feature: Add file to chat (attaches file or selected lines to the focused agent) — Status: `in flight (M3b)` ("Mention in chat" only) — Source: ticket `docs/tickets/M3-workspace-panel.md:M3b`; `docs/research/01-app-features.md:204`
- [ ] Feature: Built-in Markdown / HTML preview + source editor floor; image preview — Status: `missing` — Source: `docs/research/01-app-features.md:213`
- [ ] Feature: Editor autosave + conflict handling ("Changed on disk" / "File deleted on disk", Overwrite/Reload, "Reload from disk?") — Status: `missing` — Source: `docs/research/01-app-features.md:213`; docs/research/02-protocol-workspaces-git-files.md:492-515
- [ ] Feature: Editor find / find-and-replace — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:57,215`
- [ ] Feature: Vim keybindings (web/desktop editor) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:213,278`
- [ ] Feature: Open with… (picker for contended file types, per-extension default, "Always use") — Status: `missing` — Source: `docs/research/01-app-features.md:212`
- [ ] Feature: Open location settings (Explorer sidebar / side pane / main panel destinations) — Status: `missing` — Source: `docs/research/01-app-features.md:209,289`
- [ ] Feature: Open in editor / Reveal in file manager / Open in file manager (desktop) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:211`
- [ ] Feature: Plugin-registered file panels (viewer plugins; "File panels appear here when a plugin adds one") — Status: `missing` — Source: `docs/research/01-app-features.md:214,279`
- [ ] Feature: Live file watching (file observer, change → conflict UI) — Status: `store only (no UI)` (watch/unwatch wired in `GitExtrasStore`; `WorkspaceFiles` has no subscription; no UI consumes either) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/GitExtras.swift:339-400`; protocol `docs/research/02-protocol-workspaces-git-files.md:462,260`
- [ ] Feature: File mentions in chat render as file cards that open the file — Status: `missing` — Source: `docs/research/01-app-features.md` (assistant-file-links); protocol/spec `docs/research/05-rich-media-spec.md:397`

## Git & changes

- [ ] Feature: Working-tree diff subscription (modern binary pipeline, `diff.subscribe`) — Status: `in flight (M3c)` (store landed: `GitExtras.swift:198-245`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/GitExtras.swift:198-245`; docs/research/02-protocol-workspaces-git-files.md:230; ticket `docs/tickets/M3-workspace-panel.md:M3c`
- [ ] Feature: Legacy JSON diff subscription (fallback path) — Status: `done` (store; no UI) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/CheckoutStore.swift:131-165`; docs/research/02-protocol-workspaces-git-files.md:240-260
- [ ] Feature: Changes page (branch, ahead/behind, changed-file list with status letters and +/− counts) — Status: `in flight (M3c)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3c`; `docs/research/01-app-features.md:153`
- [ ] Feature: Unified diff view (Mono, hunk headers, line numbers, tinted add/remove backgrounds, horizontal scroll) — Status: `in flight (M3c)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3c`; `docs/research/01-app-features.md:155-156`
- [ ] Feature: Side-by-side diff toggle — Status: `missing` — Source: `docs/research/01-app-features.md:155`
- [ ] Feature: Diff compare switch (Uncommitted / vs base) — Status: `in flight (M3c)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3c`; reference `docs/research/01-app-features.md:154`
- [ ] Feature: Diff options (inline diff, hide/show whitespace, wrap/scroll long lines, collapse/expand all files) — Status: `missing` — Source: `docs/research/01-app-features.md:156`
- [ ] Feature: Commits list ahead of base; per-commit diff tabs (needs `commitsList` feature flag) — Status: `missing` (fixtures advertise the flag; no store method, no UI) — Source: `docs/research/01-app-features.md:157`; docs/research/02-protocol-workspaces-git-files.md:342
- [ ] Feature: Jump-to-file floating button in diff — Status: `missing` — Source: `docs/research/01-app-features.md:158`
- [ ] Feature: Change workspace base branch (picker; per-workspace) — Status: `missing` — Source: `docs/research/01-app-features.md:159`; docs/research/02-protocol-workspaces-git-files.md:157
- [ ] Feature: Discard changes (per file, with confirmation) — Status: `in flight (M3c)` (store landed: `GitExtras.swift:246-276`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/GitExtras.swift:246-276`; ticket `M3c`; `docs/research/01-app-features.md:160`
- [ ] Feature: Commit (host generates message from metadata model; add-all) — Status: `in flight (M3c)` (store landed: `CheckoutStore.swift:166-209`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/CheckoutStore.swift:166-209`; ticket `M3c`; `docs/research/01-app-features.md:170`
- [ ] Feature: Push (with disabled-reason handling) — Status: `in flight (M3c)` (store landed: `CheckoutStore.swift:191-209`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/CheckoutStore.swift:191-209`; ticket `M3c`; `docs/research/01-app-features.md:171`
- [ ] Feature: Pull / Pull and push / merge (fast-forward, conflicts) — Status: `missing` — Source: `docs/research/01-app-features.md:171,174`; docs/research/02-protocol-workspaces-git-files.md:312
- [ ] Feature: Commit + push + create PR split-button toolbar (with precise disabled explanations) — Status: `missing` — Source: `docs/research/01-app-features.md:166-178`
- [ ] Feature: Create PR/MR; View PR/MR; Merge PR (squash/merge/rebase); Merge MR; auto-merge enable/disable; Merge locally — Status: `missing` — Source: `docs/research/01-app-features.md:172-176`; docs/research/02-protocol-workspaces-git-files.md:389
- [ ] Feature: PR status badge ("Pull request #N" / "Merge request !N") for sidebar rows and the Changes toolbar; PR state/icon — Status: `in flight (M3c)` (store landed: `GitExtras.swift:527-620` `PullRequestBadge`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/GitExtras.swift:527-620` (`PullRequestBadge`), `:189-197`; ticket `M3c`; `docs/research/01-app-features.md:161`
- [ ] Feature: PR pane — Activity timeline (approvals, review threads, "Add to chat" per thread/comment, "Open on {{brand}}") — Status: `missing` — Source: `docs/research/01-app-features.md:163`; docs/research/02-protocol-workspaces-git-files.md:431
- [ ] Feature: PR checks section (per-check rows, failing count, "Checks passed/running/failed" rollups, Add to chat / Add all to chat) — Status: `missing` — Source: `docs/research/01-app-features.md:162`; docs/research/02-protocol-workspaces-git-files.md:410
- [ ] Feature: Forge setup callout (install `gh`/`glab`, authenticate) — Status: `missing` — Source: `docs/research/01-app-features.md:164`
- [ ] Feature: Forge search (issues/PRs for attachment pickers and branch starts) — Status: `store only (no UI)` — Source: docs/research/02-protocol-workspaces-git-files.md:420; this client: not implemented (`searchGithubRepositories` is clone-flow only); see `Packages/PaseoCore/Sources/PaseoStore/WorkspaceDirectory.swift:248-270`
- [ ] Feature: Branch switcher (combobox, "Stash & Switch" on dirty tree, restore after) — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/GitExtras.swift:277-321`; `docs/research/01-app-features.md:179-181`; docs/research/02-protocol-workspaces-git-files.md:352
- [ ] Feature: Review comments in the diff ("Leave a comment", drafts per diff mode, Send feedback (N) to an agent) — Status: `missing` — Source: `docs/research/01-app-features.md:184-185`
- [ ] Feature: Git actions split-button surfaces disabled-state reasons — Status: `missing` — Source: `docs/research/01-app-features.md:168-178`
- [ ] Feature: "Update from {{baseRef}}" (merge base into branch) — Status: `missing` — Source: `docs/research/01-app-features.md:175`; docs/research/02-protocol-workspaces-git-files.md:312
- [ ] Feature: New worktree from the new-workspace screen (branch-off, PR checkout) — See Workspaces & projects — Status: `done` (branch-off only) — Source: `docs/research/01-app-features.md:189`; this client `…/Chat/PaseoSidebar.swift:761-880`
- [ ] Feature: Git status snapshot live subscription (`checkout_status_update`) — Status: `done` (store; no UI) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/CheckoutStore.swift:106-130`; protocol `docs/research/02-protocol-workspaces-git-files.md:272`

## Terminals & scripts

- [ ] Feature: Terminals store (list, create, kill, rename-less, attach/detach, input bytes, resize with claim/update, capture, capability cache) — Status: `done` (store; no UI) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/TerminalsStore.swift`; protocol docs/research/03-protocol-terminals-scripts.md:60-460
- [ ] Feature: Terminal page (picker chips for the workspace's terminals + "New", SwiftTerm renderer) — Status: `in flight (M3d)` — Source: ticket `docs/tickets/M3-workspace-panel.md:M3d`; stub `Packages/PaseoUI/Sources/PaseoUI/Workspace/WorkspaceTerminalsView.swift`
- [ ] Feature: New terminal (from header menu / + menu / shortcut; named command via terminal profiles) — Status: `in flight (M3d)` (store supports create; no profiles yet) — Source: ticket `M3d`; `docs/research/01-app-features.md:219`; this client `TerminalsStore.createTerminal`
- [ ] Feature: Terminal tabs (live title, activity dot/ring, rename, close with confirmation) — Status: `missing` (no UI; store has no rename) — Source: `docs/research/01-app-features.md:220`; docs/research/03-protocol-terminals-scripts.md:100
- [ ] Feature: Find in terminal (find box, previous/next, No matches) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:221`
- [ ] Feature: Paste/drop a file into the terminal (path paste or remote upload, 50 MB cap) — Status: `missing` — Source: `docs/research/01-app-features.md:222`
- [ ] Feature: Local links (`path:line[:col]`) clickable → open in main pane — Status: `missing` — Source: `docs/research/01-app-features.md:223`
- [ ] Feature: Terminal activity indicators (dots/rings on tab chips, host hook reporting) — Status: `missing` — Source: `docs/research/01-app-features.md:224`; docs/research/03-protocol-terminals-scripts.md:285
- [ ] Feature: Virtual key bar + "Show/Hide keyboard" on compact/native — Status: `missing` — Source: `docs/research/01-app-features.md:225`
- [ ] Feature: Terminal scrollback setting — Status: `missing` — Source: `docs/research/01-app-features.md:226`
- [ ] Feature: Terminal agent hooks (installs into agent config files; drives notifications/status) — Status: `missing` — Source: `docs/research/01-app-features.md:227`
- [ ] Feature: Native renderer install prompt ("Update the host…") — Status: `missing` — Source: `docs/research/01-app-features.md:228`
- [ ] Feature: Workspace scripts — list with live status (`workspace.script.list`, `script_status_update` push) — Status: `in flight (M3d)` (store landed: `TerminalsStore.swift:274-330`, `Scripts.swift`) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/TerminalsStore.swift:274-330`, `Packages/PaseoProtocol/Scripts.swift`; ticket `M3d`; docs/research/03-protocol-terminals-scripts.md:375-460
- [ ] Feature: Script start/stop — Status: `in flight (M3d)` (store landed: `TerminalsStore.swift:296-330`) — Source: this client `TerminalsStore.swift:296-330`; ticket `M3d`
- [ ] Feature: Script restart — Status: `missing` (start-after-stop only) — Source: `docs/research/01-app-features.md:234`
- [ ] Feature: Script status visuals (running blue / healthy green / unhealthy red / idle, "exit N" badge) — Status: `in flight (M3d)` (status list; exact marks not specified) — Source: ticket `M3d`; `docs/research/01-app-features.md:236`
- [ ] Feature: Script proxy URLs (Reverse proxy / Memorable / Direct; Choose URL; Copy URL) — Status: `missing` (store keeps `preferredURL`; no UI) — Source: `docs/research/01-app-features.md:234,237`; this client `Packages/PaseoProtocol/Scripts.swift:59-117`
- [ ] Feature: "View service" (open URL; ask/remember in-Paseo vs external browser; Ask/In Paseo/External browser setting) — Status: `missing` — Source: `docs/research/01-app-features.md:237,289`
- [ ] Feature: Script configuration in Project settings (paseo.json: Add script, Name, Command, "Run as a service", $PASEO_PORT hint, Edit/Remove) — Status: `missing` — Source: `docs/research/01-app-features.md:238`
- [ ] Feature: Side/bottom panel placement polish (`dsh-better-sidebar`) — Status: `not applicable (DSH/web host panel plumbing)` — Source: folder `bottom-panel-fit/`
- [ ] Feature: Service health surfaced in sidebar rows — See Sidebar & navigation — Status: `missing` — Source: `docs/research/01-app-features.md:236`

## Schedules

- [ ] Feature: Schedules store (list across hosts, inspect, logs, create/update/pause/resume/run-once/delete, drafts, state machine, heartbeats) — Status: `done` (store; no UI) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/SchedulesStore.swift`, `Packages/PaseoProtocol/Schedules.swift`; tests in `Tests/`; fixtures `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/schedules/`
- [ ] Feature: Schedules screen (host picker, All hosts, Active/Ended filter, empty states, per-host load errors) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:244`; this client: no view references `session.schedules`
- [ ] Feature: Sidebar "Schedules" row — Status: `missing` (placeholder "Scheduled" row → Coming-soon sheet; no `/schedules` screen) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:163-164`; `docs/research/01-app-features.md:248`
- [ ] Feature: Schedule row (status pills Active/Paused/Expired/Finished/Target gone, last/next run, pause/resume, Run now, edit, delete) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:245`; this client `SchedulesStore.swift:51-360,421-470`
- [ ] Feature: Schedule form sheet (New/Edit schedule/heartbeat: Name, Prompt, Max runs "Unlimited", Host, Project, Model, Thinking, Mode, Archive on finish, Isolation Local/Worktree, Cadence editor) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:246`; this client `SchedulesStore.swift:364-420` (`ScheduleDraft`, `ScheduleEdits`, `ScheduleCadence`)
- [ ] Feature: Heartbeats (cron prompt back into the same agent; created from agent surfaces/CLI; same form, "Edit heartbeat" title) — Status: `store only (no UI)` — Source: `docs/research/01-app-features.md:247`; this client `SchedulesStore.createHeartbeat`, `Packages/PaseoProtocol/Schedules.swift`
- [ ] Feature: Cadence editor (cron builder) — Status: `store only (no UI)` (model only; no editor view) — Source: `docs/research/01-app-features.md:246`; this client `SchedulesStore.swift` (`ScheduleCadence`)
- [ ] Feature: Schedules UI built on the T9 store — planned M4; an unwired ClaudeUI `ClaudeRoutinesView` exists but predates the Paseo store and is not reachable — Status: `store only (no UI)` — Source: `docs/STATUS.md:68-69`; this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeRoutinesView.swift` (dead code)
- [ ] Feature: Schedule live updates — no push channel exists; the screen must poll/refresh — Status: `not applicable (protocol has no schedule-update push; `load()`/`refresh()` only — noted for M4 design)` — Source: this client `SchedulesStore.swift:57-81`; `docs/research/04-protocol-agents-permissions-settings.md:1359`

## Settings

- [ ] Feature: Settings surface — App + Host groups with split view on wide layouts — Status: `missing` (a minimal sheet exists: theme, your name, host status, Disconnect) — Source: `docs/research/01-app-features.md:268`; this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSidebar.swift:611-758`
- [ ] Feature: Your name setting (feeds the home greeting) — Status: `done` — Source: this client `…/Chat/PaseoSidebar.swift:638-647`, `Packages/PaseoUI/Sources/PaseoUI/Chat/ClaudeHomeHero.swift`; `docs/research/06-dsh-ux-spec.md` (home greeting)
- [ ] Feature: Appearance — theme picker with System/Light/Dark — Status: `done` — Source: this client `…/Chat/PaseoSidebar.swift:619-633`
- [ ] Feature: Appearance — full theme list (Light/Dark/Zinc/Midnight/Claude/Ghostty/Pure black/System) + live preview — Status: `missing` — Source: `docs/research/01-app-features.md:273`
- [ ] Feature: Appearance — fonts (interface font/size, content size, code font/size) — Status: `missing` — Source: `docs/research/01-app-features.md:273`
- [ ] Feature: Appearance — content width (px, reset), syntax highlight theme — Status: `desktop-only (flag)` (web/desktop) — Source: `docs/research/01-app-features.md:273`
- [ ] Feature: Chat settings (always expand reasoning; chat display mode Full/Collapse tool calls/Collapse turns; chat outline toggle) — Status: `missing` — Source: `docs/research/01-app-features.md:275`
- [ ] Feature: Terminal settings (scrollback lines; terminal profiles are host-scoped) — Status: `missing` — Source: `docs/research/01-app-features.md:276`
- [ ] Feature: General — Language dropdown (10 locales) — Status: `missing` — Source: `docs/research/01-app-features.md:272`
- [ ] Feature: General — Sending card (Send shortcut Enter vs ⌘/Ctrl+Enter; Default send Interrupt/Steer/Queue) — Status: `missing` — Source: `docs/research/01-app-features.md:272`
- [ ] Feature: General — "Show setup again" — Status: `missing` — Source: `docs/research/01-app-features.md:272`
- [ ] Feature: Sidebar settings — Sidebar view picker + Header/Footer rows (reorder up/down, visibility switches, shortcut badges, usage row hidden by default) — Status: `missing` — Source: `docs/research/01-app-features.md:274`
- [ ] Feature: Shortcuts settings (capture/rebind/clear/reset; sections General/Projects/Tabs/Layout/Agent Input; "Reset all") — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:280`
- [ ] Feature: Diagnostics — App diagnostic report (copyable) + "Test audio" Play/Playing… — Status: `missing` — Source: `docs/research/01-app-features.md:284`
- [ ] Feature: About — App version, What's new (changelog), Release channel (Stable/Beta), App updates (Check/Update), Connected hosts (daemon versions, mismatch hint), community links — Status: `missing` — Source: `docs/research/01-app-features.md:285`
- [ ] Feature: Files settings — contended file-type selector (default panel per extension, "Ask every time", Ask again) — Status: `missing` — Source: `docs/research/01-app-features.md:279`
- [ ] Feature: Integrations — install/uninstall `paseo` CLI — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:281`
- [ ] Feature: Notifications settings (notification permission row, Play sound, Test notification) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:282`
- [ ] Feature: Permissions settings (Microphone row) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:283`
- [ ] Feature: Open location section (where files/changes/PR/service URLs open: Main panel / On the side / Explorer sidebar / Ask/In Paseo/External browser) — Status: `missing` — Source: `docs/research/01-app-features.md:289`
- [ ] Feature: Host sections (Overview, Projects, Connections, Pair device, Agents, Metadata, Voice, Workspaces, Providers, Usage, Terminals, Plugins) — See Connection & hosts — Status: `missing` (store-only where noted) — Source: `docs/research/01-app-features.md:293`
- [ ] Feature: Project settings (paseo.json: name, icon, hooks, scripts, metadata prompts) — See Workspaces & projects — Status: `missing` — Source: `docs/research/01-app-features.md:141`
- [ ] Feature: Sidebar identity/avatar initial from Your name — Status: `done` — Source: this client `…/Chat/PaseoSidebar.swift` (`initial`, footer avatar)

## Notifications & attention

- [ ] Feature: Attention badge on workspace rows / unread dot — Status: `done` — Source: this client `…/Chat/PaseoSidebar.swift:323-327,347-361` (`attention`, `PaseoStatusDot(kind: .unread)`)
- [ ] Feature: Opening an agent clears its attention flag (daemon-side) and refreshes the list — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoShellView.swift:197-210`; `HostSession.refreshAgents`
- [ ] Feature: OS notification when an agent turn finishes needing input — Status: `missing` (no `UNUserNotificationCenter` anywhere; daemon `agent_attention_required` is decoded but nothing raises a notification) — Source: `docs/research/01-app-features.md:337`; `rg -il "UNUserNotificationCenter" App Packages` → nothing
- [ ] Feature: Attention notifications for terminals — Status: `missing` — Source: `docs/research/01-app-features.md:338`
- [ ] Feature: Notification tap → route to the agent/workspace (pinned, navigation-ready, deduped) — Status: `missing` — Source: `docs/research/01-app-features.md:339`
- [ ] Feature: Attention OS notifications are suppressed while viewing that agent / pure errors skipped — Status: `missing` — Source: `docs/research/01-app-features.md:337`
- [ ] Feature: Desktop dock/taskbar badge count of attention-tagged workspaces — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:337`
- [ ] Feature: Notification permission + sound + test-notification settings — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:340`
- [ ] Feature: Expo push token registration per host (native; cached; refetch on reconnect; Android channel) — Status: `store only (no UI)` (register/unregister wired; never called from the app) — Source: this client `Packages/PaseoCore/Sources/PaseoStore/HostSettingsStore.swift:226-250`; `docs/research/01-app-features.md:341`
- [ ] Feature: Terminal-attention pipeline feeds the same notification path — Status: `missing` — Source: `docs/research/01-app-features.md:338`
- [ ] Feature: In-app toast surface for notices (e.g. "Workspace archived", action errors) — Status: `done` — Source: this client `…/Chat/PaseoShellView.swift` (toast overlay), `…/Chat/PaseoSidebar.swift:527-535`

## Rich content

- [ ] Feature: Assistant prose is Markdown (headings, lists, blockquotes, tables, HR, bold/italic, links) — Status: `done` — Source: this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeMarkdownView.swift`; `docs/research/08-dsh-live-observation.md:564-606`
- [ ] Feature: Fenced code blocks with language header + syntax token coloring + expanded-sheet view + Copy — Status: `done` — Source: this client `…/ClaudeChatComponents.swift` (`ClaudeCodeBlock`), `Packages/PaseoUI/Sources/PaseoUI/ClaudeCodeHighlighter.swift` (highlight.js via JavaScriptCore), `Packages/PaseoUI/Sources/PaseoUI/ClaudeMarkdownView.swift:47-99`
- [ ] Feature: Inline code (5 % ink wash, radius 4, 12–13 pt mono) — Status: `done` — Source: this client `…/ClaudeChatComponents.swift` (`ClaudeSelectableInlineCode`, `ClaudeMarkdownTheme`)
- [ ] Feature: Links open externally (prose link color `#184F95` / `#8AB4F8`) — Status: `done` — Source: this client `…/Chat/ClaudeChatView.swift` (`handleMarkdown(.openLink)`), `…/Chat/ClaudeStyle.swift` (`proseLink`)
- [ ] Feature: Images in prose (`![alt](url)`) — Status: `missing` (`ClaudeMarkdownView` supports `imageContent` but no caller passes it; `ClaudeMediaView` exists unwired) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeMarkdownView.swift:51-63,137-138`; `docs/research/05-rich-media-spec.md:266`
- [ ] Feature: Bare image URLs linkified into images — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:359`
- [ ] Feature: Local image paths (absolute/relative) render as images — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:397`
- [ ] Feature: Raw SVG blocks rendered inline — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:442`
- [ ] Feature: YouTube (fence, bare URL, in-sentence player) — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:146`; detector: this client `Packages/PaseoCore/Sources/PaseoStore/Rich/RichContentDetector.swift` (`YouTubeReference`, `YouTubeURLHit`) — `store only (no UI)`
- [ ] Feature: Link cards (standalone bare link → unfurl card) — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:66`; detector: `RichContentDetector.swift` (`RichContentBlock`) — `store only (no UI)`
- [ ] Feature: Maps (map card for addresses/coordinates) — Status: `missing` — Source: `docs/research/05-rich-media-spec.md` (referenced by rich registry in `ARCHITECTURE.md:73-77`); no detector entry
- [ ] Feature: The ` ```visualize ` fence + viz panel (interactive viz bridge) — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:479,2`
- [ ] Feature: Rich content detection (link/YouTube/image/file segments from message text) — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/Rich/RichContentDetector.swift:15-120`; unit tests `Packages/PaseoCore/Tests/PaseoStoreTests/Rich/RichContentDetectorTests.swift`
- [ ] Feature: File cards in prose (file path → card that opens the file/editor) — Status: `missing` — Source: `docs/research/05-rich-media-spec.md:397,1.8`
- [ ] Feature: Assistant-file links (link to a path in the workspace opens it) — Status: `missing` — Source: `assistant-file-links/` in the reference app; no equivalent in this client
- [ ] Feature: Media viewer (full-screen image/media grid from the dead ClaudeUI codebase) — Status: `missing` (unwired `ClaudeMediaView`/`MediaState.swift` are ClaudeUI leftovers, not Paseo-aware) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeMediaView.swift`, `MediaState.swift`

## Mascot

- [ ] Feature: T13 mascot state machine (priority: reaction 10 > error 8 > notification 7 > compacting 6 > happy 5 > subagents 4 > working 3 > thinking 2 > idle 1; 1 s min-show; 60 s quiet → sleeping; idle extras every 20–40 s) — Status: `store only (no UI)` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/Rich/MascotState.swift`; spec `docs/research/06-dsh-ux-spec.md:156-176`, confirmed live `docs/research/08-dsh-live-observation.md:657-690`
- [ ] Feature: Crab (Clawd) sprite sheets, ink-mask fill, crop boxes, 80 ms frame pace — Status: `missing` — Source: spec `docs/research/06-dsh-ux-spec.md:142,156`; observed `docs/research/08-dsh-live-observation.md:609-655`
- [ ] Feature: Deepy / Whalegirl sprite sheets (vectorized/routed) — Status: `missing` — Source: `docs/research/06-dsh-ux-spec.md:144,146`
- [ ] Feature: Mascot placement — stands on the composer card's top-right edge, above it, right-anchored; hidden until first frame — Status: `missing` — Source: `docs/research/08-dsh-live-observation.md:611-633`
- [ ] Feature: Mascot animation ↔ agent state binding (thinking↔typing alternation observed live; end-of-turn happy 5.2 s) — Status: `store only (no UI)` — Source: observed `docs/research/08-dsh-live-observation.md:657-680`; machine `Rich/MascotState.swift`
- [ ] Feature: Idle extras + 60 s quiet → sleeping; reduced-motion stills — Status: `store only (no UI)` — Source: machine `Rich/MascotState.swift`; `docs/research/06-dsh-ux-spec.md:172,189`
- [ ] Feature: Press reactions (poke-left/right, tickle at 4 taps/450 ms, drag at ≥4 px) — Status: `missing` (reaction state exists in the machine; no view, no sheets) — Source: `docs/research/06-dsh-ux-spec.md:164,189`
- [ ] Feature: Hover bubble (250 ms open; DeepSeek balance + conversation cost) — Status: `missing` (Paseo has no balance source; conversation-cost line could reuse the context-meter data once it exists) — Source: `docs/research/06-dsh-ux-spec.md:190`
- [ ] Feature: Mascot on the chat page in this client — Status: `missing` (the only in-repo mascot is a static sleeping canvas in unwired ClaudeUI `ClaudeCodeDraftView.swift:171-198`) — Source: this client `Packages/PaseoUI/Sources/PaseoUI/ClaudeCodeDraftView.swift:171-198`
- [ ] Feature: Mascot licensing decision recorded (crab = Anthropic's character; personal, non-distributed app; reuse tolerated, not licensed) — Status: `done` (decision recorded) — Source: `docs/research/06-dsh-ux-spec.md:209-237`; this client: bundled fonts are Anthropic faces + Newsreader/JetBrains Mono substitutes (`Packages/PaseoUI/Sources/PaseoUI/Resources/`); decision `docs/STATUS.md:71`

## Search & history

- [x] Feature: Sessions / History screen — See Workspaces & projects — Status: `done` (History sheet: agents across workspaces, newest first, Today/Yesterday/Earlier grouping, title filter; active agents only, tap opens the agent) — Source: this client `Chat/ClaudeHistoryView.swift`; `docs/research/01-app-features.md:135`
- [x] Feature: Timeline search (query the agent's timeline through the daemon; match positions; paginate) — Status: `done` — Source: this client `Packages/PaseoCore/Sources/PaseoStore/ConversationSearch.swift`, `Packages/PaseoProtocol/TimelineSearch.swift`; UI: `Chat/ClaudeChatView.swift` (find bar, scroll-to-match, brief highlight, expands the work group holding the match), `Chat/ClaudeFindBar.swift`; docs/research/04-protocol-agents-permissions-settings.md:889; fixtures `Packages/PaseoCore/Tests/PaseoFixtures/Fixtures/attachments-search/`
- [ ] Feature: Command center (Cmd+K: Actions / Files / Workspaces / Agents / Models / Thinking / Mode / Fast groups, keyboard-driven, shortcut badges) — Status: `missing` — Source: `docs/research/01-app-features.md:252-264`
- [ ] Feature: Command palette in DSH style (redraw of the host palette; searches sessions/projects/actions) — Status: `missing` — Source: folder `dsh-claude-style-reference/packages/client/src/features/search/` (Ctrl+K takeover, Recents/Actions/Sessions/Projects filters)
- [ ] Feature: Keyboard shortcuts dialog (all bindings, grouped, "Not set" states) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:408`
- [ ] Feature: "Search" placeholder/action in sidebar — See Sidebar & navigation — Status: `missing` — Source: `docs/research/01-app-features.md:99`
- [x] Feature: Search history (History screen: "Search history") — Status: `done` (title filter in the History screen) — Source: this client `Chat/ClaudeHistoryView.swift`; `docs/research/01-app-features.md:137,293-300`
- [ ] Feature: Find in pane — See Desktop-only — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:57`
- [ ] Feature: Slash-command search in the composer — See Composer — Status: `done` (the `/` menu filters as you type) — Source: `docs/research/01-app-features.md:89`; this client `…/Chat/ClaudeChatView.swift`

## Voice

- [ ] Feature: Dictation (mic → overlay with timer + live volume meter + transcript; cancel / insert / insert-and-send; retry; mic glyph red while recording; `dictation-toggle` shortcut) — Status: `missing` — Source: `docs/research/01-app-features.md:350`; docs/research/04-protocol-agents-permissions-settings.md:1280
- [ ] Feature: Voice mode (realtime conversation, mic-disc button in the composer, live volume meter, mute, interrupt, thinking tone) — Status: `missing` — Source: `docs/research/01-app-features.md:349`; docs/research/04-protocol-agents-permissions-settings.md:1253-1343
- [ ] Feature: Voice settings (host → Voice: Dictation switch, STT row; Voice mode switch; Listening/Speaking provider rows) — Status: `missing` — Source: `docs/research/01-app-features.md:301,351`
- [ ] Feature: Speech provider sheets (Local: model catalog + download/delete, sizes, recommended; OpenAI: API key/Base URL/model/language/voice) — Status: `missing` — Source: `docs/research/01-app-features.md:352`
- [ ] Feature: Local speech model management (`speech.local_models.list/download/delete`) — Status: `missing` — Source: docs/research/04-protocol-agents-permissions-settings.md:1343
- [ ] Feature: Test audio diagnostic — See Settings — Status: `missing` — Source: `docs/research/01-app-features.md:284`
- [ ] Feature: Keep awake while voice mode is live — Status: `missing` — Source: `docs/research/01-app-features.md:354`
- [ ] Feature: Voice presence/config in daemon config (`HostSettings.Usage` is decoded; speech config block not mapped) — Status: `store only (no UI)` (partial) — Source: this client `Packages/PaseoProtocol/HostSettings.swift:114-180`; docs/research/04-protocol-agents-permissions-settings.md:1240

## Desktop-only

- [ ] Feature: Desktop window chrome (hidden title bar, drag regions, minimize/maximize/close, sidebar toggle) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:402`
- [ ] Feature: Focus mode (hide chrome for the workspace; "Exit focus mode") — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:118,402`
- [ ] Feature: Split panes / move tabs between panes / maximize pane — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:118,123`
- [ ] Feature: Built-in local daemon (desktop: managed daemon, quitting overlay "Stopping the local daemon", Rosetta callout) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:366,402-404`
- [ ] Feature: Desktop app updates (auto-check, "{{version}} is ready to install" callout, Update to {{version}}, Stable/Beta channel) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:285,403`
- [ ] Feature: Release channel setting (Stable/Beta) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:285`
- [ ] Feature: Changelog sheet ("What's new") — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:406`
- [ ] Feature: App diagnostic report (Run) — Status: `missing` (not inherently desktop; worth building on iOS) — Source: `docs/research/01-app-features.md:407`
- [ ] Feature: Desktop notifications (permission row, Play sound, Test notification) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:282,340`
- [ ] Feature: OS permissions for desktop (Microphone) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:283`
- [ ] Feature: Integrations — `paseo` CLI install switch — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:281`
- [ ] Feature: Built-in browser pane (tabs, Back/Forward/Reload, URL bar, dev tools, element annotation, screenshot, device-size picker, "Browser is desktop-only" elsewhere) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:124`
- [ ] Feature: Browser data (cookies/site data; destructive Clear browser data) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:277`
- [ ] Feature: Remote SSH connection — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:360`
- [ ] Feature: Vim keybindings in the editor (web/desktop) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:278`
- [ ] Feature: Chat outline rail (web/desktop wide screens) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:56`
- [ ] Feature: Find in pane (web-only chat; shared by terminals and file editor with replace) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:57`
- [ ] Feature: Native terminal renderer install prompt (host-side native renderer) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:228`
- [ ] Feature: Open in editor / Reveal in file manager (desktop/web header split button) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:211`
- [ ] Feature: Header-band / caption-row integration (session title + controls into the window caption) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md` (Electron); folder `header-band/`
- [ ] Feature: Quitting overlay — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:33,402`
- [ ] Feature: Desktop release/update channel + What's new row — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:285`
- [ ] Feature: Keyboard shortcuts (bindings, rebind, capture, Reset all; hardware-keyboard settings) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:280`
- [ ] Feature: Keyboard shortcuts dialog — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:408`
- [ ] Feature: Rosetta callout — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:404`
- [ ] Feature: Download toast (file downloads with progress/speed/ETA) — Status: `desktop-only (flag)` — Source: `docs/research/01-app-features.md:405`
- [ ] Feature: Pinned-window usage meters in the sidebar footer — Status: `missing` (not inherently desktop; needs the whole usage pipeline — see Rich content / M-milestones) — Source: `docs/research/01-app-features.md:395`

## DSH Claude-style plugin — folder inventory (every folder, one row)

One row per `packages/client/src/features/<name>/` in `/home/paseo/dev/dsh-claude-style-reference`
(47 folders, listed alphabetically-ish by area as they cluster). Each row says what the folder does
and what this client does about it. For user-facing *behavior* details, see the area sections above
and `docs/research/06-dsh-ux-spec.md` / `08-dsh-live-observation.md`.

- [ ] Feature: `account` — self-built account drawer + footer rows (avatar, settings entry, plugin row, collapse preference) for hosts without an account row — Status: `not applicable (Paseo has no account concept; the app footer is ours)` — Source: `…/features/account/` (`account-drawer.ts`, `account-footer.ts`, `host-menu.ts`)
- [ ] Feature: `active-first` — keeps running rows at the head of the session list — Status: `missing` — Source: `…/features/active-first/` (`active-first.ts`); ours sorts by activity, not by running state
- [ ] Feature: `active-shelf` — "Group by date / by workspace" toggle above the sidebar list — Status: `missing` — Source: `…/features/active-shelf/` (`active-shelf.ts`, copy `viewByDate`/`viewByWorkspace`)
- [ ] Feature: `ban-screen` — account-hold easter-egg page ("Your account is on hold", export/delete data steps) — Status: `not applicable (DeepSeek account page; Paseo has no accounts)` — Source: `…/features/ban-screen/` (`ban-screen.ts`, `ban-screen.copy.json`)
- [ ] Feature: `bottom-panel-fit` — places `dsh-better-sidebar`'s bottom panel in page pixels under web zoom — Status: `not applicable (web host zoom plumbing)` — Source: `…/features/bottom-panel-fit/` (`bottom-panel-fit.ts`)
- [ ] Feature: `brand` — custom brand layer (reader's own name, images, four colors over the chosen brand) — Status: `not applicable (web skin personalization; our palette is fixed)` — Source: `…/features/brand/` (`brand.ts`, `PALETTE_CARDS`)
- [ ] Feature: `caret` — custom 2 px accent caret, 80 ms glide, 1 s step-end blink (native caret hidden via `caret-color: transparent`) — Status: `missing` — Source: `…/features/caret/` (`caret.ts`, `caret-measure.ts`, `caret.css`); measured `docs/research/08-dsh-live-observation.md:468-507`; our code has no caret animation
- [ ] Feature: `chat-anchor` — anchors the answer's first line to the top of the conversation when generation begins — Status: `missing` — Source: `…/features/chat-anchor/` (`chat-anchor.ts`)
- [ ] Feature: `chat-files` — file-call rows for Read/Edit/Write: verb + dotted-underline file name, merged per file, diff stats, expandable body with line numbers — Status: `missing` — Source: `…/features/chat-files/` (`chat-files.ts`, `file-row-model.ts`, `file-row-merge.ts`); measured `docs/research/08-dsh-live-observation.md:133-160`
- [ ] Feature: `chat-fold` — process-group folding: counted header ("{n} thoughts, {n} tool calls"), digit roll (160 ms), fold "door" (200 ms), reasoning replay window (400 px cap), user-message clamp (320 px) — Status: `done` — Source: `…/features/chat-fold/` (`process-fold.ts`, `process-summary.ts`, `fold-glide.ts`, `reasoning-fold.ts`, `message-fold.ts`); this client `ClaudeWorkGroupCell`/`ClaudeStepRow` in `…/Chat/ClaudeChatView.swift`
- [x] Feature: `chat-follow` — chat follow: keeps the tail in view as it streams, holds when the reader scrolls, and re-places the host's "back to end" button (12 px above the composer, centered) — Status: `done` — Source: `…/features/chat-follow/` (`chat-follow.ts`, `process-follow.ts`, `chat-follow.css`); this client `…/Chat/ClaudeChatView.swift` (`isFollowing`, `onScrollGeometryChange`, `backToEnd`, `transcriptFade`)
- [ ] Feature: `chat-reveal` — new arriving assistant text fades in per character via CSS `::highlight()` ranges (24-step, ~2.4 ms stagger, 120 ms) — Status: `missing` — Source: `…/features/chat-reveal/` (`reveal-engine.ts`, `reveal-paint.ts`, `reveal-params.ts`)
- [ ] Feature: `chat-send` — message-bubble enter animation ("grow into its place" or "fly up from the composer", two reader choices) — Status: `done` (grow-in-place variant) — Source: `…/features/chat-send/` (`send-flight.ts`, `send-grow.ts`, `send-morph.ts`); this client `…/Chat/ClaudeChatComponents.swift`
- [ ] Feature: `chat-wait` — the waiting line: fixed state wording + model's own words (file/command/reasoning clause), 1 s wording lock, 250 ms tick, sweep/wash, loader dots (3 lanes, 10 s rotation), 10 s overtime badge, turn clock — Status: `done` — Source: `…/features/chat-wait/` (`wait-state.ts`, `chat-wait.ts`, `wait-loader.ts`); this client `…/Chat/ClaudeStatusLine.swift`, `…/Chat/ClaudeLoader.swift`, `…/Chat/ClaudeReasoningClause.swift`; measured `docs/research/08-dsh-live-observation.md:212-425`
- [ ] Feature: `composer` — composer restyle (hero card on home / flat 14 px conversation bar; radius, focus halo, bottom gap preference, placeholder "Type / for commands", two-tier footer tray on the classic layout) — Status: `done` (our composer is restyled but drifts: 27 pt capsule, filled orange circle send, no drawn caret; placeholder is "Type / for commands" when the agent reports commands) — Source: `…/features/composer/` (`card.css`, `inline.css`, `composer.ts`); measured `docs/research/08-dsh-live-observation.md:427-507`; this client `…/Chat/ClaudeChatView.swift`
- [ ] Feature: `context-stats` — context meter (pie or ring, ramped green→red) + session stats line (cost, total time) in the composer footer; billing table editor — Status: `missing` — Source: `…/features/context-stats/` (`meter-ring.ts`, `session-cost.ts`, `context-stats.ts`); we show no context usage anywhere
- [ ] Feature: `conversation-width` — conversation column width factor (75 % / 50 % / 100 % of the window) — Status: `not applicable (single-column iPhone layout; no width handle to drag)` — Source: `…/features/conversation-width/` (`conversation-width.ts`)
- [ ] Feature: `date-groups` — date section headers in the sidebar list (Today / Yesterday / weekday names / Earlier) — Status: `missing` — Source: `…/features/date-groups/` (`date-groups.ts`, `date-groups.copy.json`)
- [ ] Feature: `effort` — reasoning-effort slider with accent tint on the effort button ("Faster/Smarter" ladder) — Status: `missing` (thinking picker exists as a plain list — see Agents & models) — Source: `…/features/effort/` (`effort-picker.ts`, `slider.ts`, `ladder.ts`, `tint.ts`)
- [ ] Feature: `header-band` — session title + header controls rise into the OS caption row; collapses the right panel — Status: `desktop-only (flag)` — Source: `…/features/header-band/` (`header-band.ts`, copy `headerBandTitle`)
- [ ] Feature: `hero-menu` — hero-page pickers: the workspace (directory) chip and the agent-preset seat — Status: `missing` (greeting hero only; no pickers) — Source: `…/features/hero-menu/` (`hero-menu.ts`)
- [ ] Feature: `home` — home page with overview/models usage charts (token heat, peak hour, "animal farm" fun comparisons), usage refresh — Status: `missing` (home is a greeting + asterisk hero; no stats) — Source: `…/features/home/` (`home-figures.ts`, `overview.ts`, `home-store.ts`, `greetings.ts` — greetings are ported); this client `…/Chat/ClaudeHomeHero.swift`
- [ ] Feature: `home-ripple` — ripple glyph background on the new-conversation page (press ripples through digits/letters) — Status: `missing` — Source: `…/features/home-ripple/` (`home-ripple.ts`, `ripple-field.ts`)
- [ ] Feature: `manual-unread` — right-click "Mark as unread" / "Clear unread mark" on a session row — Status: `missing` — Source: `…/features/manual-unread/` (`manual-unread.ts`, `row-mark.ts`)
- [ ] Feature: `mascot` — Clawd (crab) / Deepy / Whalegirl pixel mascots on the composer's top-right edge; one state machine; reactions on press; hover bubble (balance + session cost); 60 s sleep — Status: `store only (no UI)` — Source: `…/features/mascot/` (`mascot-stage.ts`, `mascot-signals.ts`, `mascot-player.ts`, `sheets.ts`, `crab.ts`, `whale.ts`, `whale-girl.ts`); spec `docs/research/06-dsh-ux-spec.md:136-195`; observed `08-…md:609-703`; this client `Packages/PaseoCore/Sources/PaseoStore/Rich/MascotState.swift` (T13)
- [ ] Feature: `message-actions` — the reader message action row (Retract / Edit / Rerun / Delete, incl. "Run this turn again in a new session") — Status: `missing` — Source: `…/features/message-actions/` (`message-action-buttons.ts`, `message-cut.ts`, copy `retract`/`edit`/`rerun`/`delete`)
- [ ] Feature: `model` — Claude-style model picker: brand marks per vendor, model descriptions, search, quick providers, level-one list, release tags — Status: `done` (functional picker with provider/mode/thinking; no brand marks, descriptions, quick-provider level or search) — Source: `…/features/model/` (`model-picker.ts`, `brand.ts`, `rows.ts`, `catalog.ts`); this client `…/Chat/ClaudeAgentControlsSheet.swift`, `…/Chat/ClaudeNewAgentSheet.swift`
- [ ] Feature: `peakrate` — peak/off-peak/promotion rate badges + countdown on every model row — Status: `not applicable (DeepSeek peak-pricing feed; Paseo has no such data)` — Source: `…/features/peakrate/` (`peakrate.ts`, `schedule.ts`, `badge.ts`)
- [ ] Feature: `permissions` — redraws the composer permission/access control (Claude-style segment group / trigger + card) — Status: `missing` (inline permission cards exist — see Permissions section) — Source: `…/features/permissions/` (`permissions.ts`, `permission-tier-card.ts`, `permission-catalog.ts`)
- [ ] Feature: `process-column` — the column layout of process rows: one line per row, 0.5 px dividers, 4 px gaps, trailing chevron on disclosure rows, card grows with rows or caps at `min(400px, 50vh)` — Status: `done` — Source: `…/features/process-column/` (`process-column.ts`, `process-column.css`); this client `…/Chat/ClaudeChatView.swift` (`ClaudeStepRow`, `card`), `docs/research/08-dsh-live-observation.md:44-174`
- [ ] Feature: `question-card` — model question card restyled to Claude look, moved to the end of the conversation — Status: `missing` — Source: `…/features/question-card/` (`question-card.ts`); this client renders `.kind == .question` as the generic permission card
- [ ] Feature: `rightbar-fit` — right panel's box in page pixels under web zoom (panel vs track mismatch) — Status: `not applicable (web host zoom plumbing)` — Source: `…/features/rightbar-fit/` (`rightbar-fit.ts`)
- [ ] Feature: `row-skip` — `content-visibility: auto` skip-marking of settled transcript rows (paint/layout perf) — Status: `not applicable (SwiftUI LazyVStack; web layout engine)` — Source: `…/features/row-skip/` (`row-skip.ts`, `row-skip.css`)
- [ ] Feature: `search` — Ctrl+K command palette takeover of the host sidebar search (Recents / Actions / Sessions / Projects / Plugins / Skills / Shortcuts, filters, keyboard-driven) — Status: `missing` — Source: `…/features/search/` (`search.ts`, `sources.ts`, `search-host-takeover.ts`)
- [ ] Feature: `session-actions` — session-row context menu (right-click → the host menu's commands: rename/archive/…) — Status: `missing` (workspace rows have a long-press menu; agent rows and their actions are missing — See Sidebar & navigation) — Source: `…/features/session-actions/` (`session-actions.ts`, `context-menu.ts`); this client `…/Chat/PaseoSidebar.swift` (workspace context menu only)
- [ ] Feature: `session-title` — header session title is the session's own name; press to edit inline, rename via host `session.rename` — Status: `missing` (no agent rename UI — See Agents & models) — Source: `…/features/session-title/` (`session-title.ts`)
- [ ] Feature: `settings` — the plugin's seven settings tabs (general/appearance/sidebar/icons/main-window/zoom/motion) incl. theme style, auto-popover, quick providers, page zoom, reasoning display — Status: `missing` (our sheet has theme + your name + host + Disconnect) — Source: `…/features/settings/` (`settings.ts`, `settings-tab-*.ts`); this client `…/Chat/PaseoSidebar.swift` (`ClaudeSidebarSettingsSheet`)
- [ ] Feature: `sidebar-entries` — edit which panel entries appear in the sidebar ("Edit sidebar…") — Status: `not applicable (DSH entry editor; our sidebar content is fixed — Paseo's own sidebar customization is a separate row, `missing`)` — Source: `…/features/sidebar-entries/` (`sidebar-entries.ts`, `more-placement.ts`)
- [ ] Feature: `sidebar-peek` — collapsed sidebar peeks open while the pointer rests on its toggle — Status: `not applicable (touch UI has no hover; drawer opens on tap/edge-drag)` — Source: `…/features/sidebar-peek/` (`sidebar-peek.ts`)
- [ ] Feature: `sidebar-status` — running marker side (left/right) and marker look (hollow/ring/breathe) preference — Status: `not applicable (our status dot is fixed left, DSH geometry ported)` — Source: `…/features/sidebar-status/` (`sidebar-status.ts`, `row-status.ts`); this client `…/Chat/PaseoSidebar.swift` (`PaseoStatusDot`)
- [ ] Feature: `sodium` — Sodium stylesheet-rewrite rendering engine (perf; PolyForm Shield licensed) — Status: `not applicable (web rendering engine; do not port; license)` — Source: `…/features/sodium/` (`sodium.ts`, `sodium-engine.ts`, `sodium/LICENSE`)
- [ ] Feature: `sound-cues` — attention sound when a task finishes or is blocked (soft/clear levels) — Status: `missing` (haptics only) — Source: `…/features/sound-cues/` (`sound-cues.ts`, `synth.ts`, `attention-feed.ts`)
- [ ] Feature: `surface` — interface switch between Chat and Code surfaces — Status: `not applicable (no second surface; chat only)` — Source: `…/features/surface/` (`surface.ts`)
- [ ] Feature: `turn-nav` — redrawn message navigator (numbered turn rail in the transcript margin) — Status: `missing` — Source: `…/features/turn-nav/` (`turn-nav.ts`, `turn-nav-host.ts`)
- [ ] Feature: `view-tabs` — Chat / Trajectory tab bar on the conversation view — Status: `not applicable (no trajectory view)` — Source: `…/features/view-tabs/` (`view-tabs.ts`)
- [ ] Feature: `width-handle` — conversation column width drag handle with hover reveal — Status: `not applicable (no resizable panels)` — Source: `…/features/width-handle/` (`width-handle.ts`)
- [ ] Feature: `workspace` — Active / Archived switch above the workspace list; archived conversations get their own list where they can be deleted — Status: `missing` — Source: `…/features/workspace/` (`workspace-view.ts`, `archived-list.ts`, `archived-actions.ts`); this client has per-item archive but no archived view


## Counts

420 feature rows. Status counts (normalized; parenthetical qualifiers ignored):

| Status | Count | Share |
|---|---|---|
| `done` | 91 | 22 % |
| `missing` | 215 | 51 % |
| `desktop-only (flag)` | 46 | 11 % |
| `store only (no UI)` | 31 | 7 % |
| `in flight` (M3a 1 · M3b 5 · M3c 8 · M3d 5) | 19 | 5 % |
| `not applicable` | 18 | 4 % |
| **Total** | **420** | 100 % |

What the numbers say: the client reaches parity almost exactly in the *conversation* area
(turn layout, DSH live-observation turn UX, permissions, markdown, markdown code blocks) and in
*connection/discovery/store plumbing* (T1–T13 all merged, fixtures-tested; a growing number are
now wired into the UI — presence, slash commands, the mascot, rich content), and is
almost entirely absent everywhere else. Roughly a fifth of the not-done rows already have their
store or their ticket landed — those need screens, not backend work.

Uncounted but present in the repo and worth naming: the unwired ClaudeUI leftover screens
(`ClaudeCodeView` / `ClaudeCodeSettingsView` / `ClaudeSettingsView` / `ClaudeRoutinesView` /
`ClaudeUsageSettingsView` / `ClaudeProjectsView` / `ClaudeMediaView` / `ClaudeVoiceSettingsSheet` /
…) are dead code, were never marked `done` here, and are candidates for M4–M9 where the row says so.


## Suggested milestones

Grouping the missing items; dependencies first, highest daily value first. M3 (panel / files /
changes / terminal) is already in flight and stays the base everything else lands on.

1. **M4 — Settings & hosts.** Make the merged-but-invisible T10 store usable by building the
   settings shell — host pages (Overview, Projects, Connections, Providers, Terminals), app
   sections (Appearance, Chat, Sidebar), provider enable/disable and agent profiles — so the app
   stops being a chat toy and becomes a console.
2. **M5 — Schedules & attention.** Wire the merged-but-invisible T9 store into a Schedules screen
   (list, form, heartbeats, pause/resume/run-now) and finish the attention loop the daemon already
   speaks (OS notifications + push registration + deep-link routing), because an agent that needs
   you on a phone is the product promise.
3. **M6 — Rich content & attachments.** Land the merged-but-invisible T13 detector end to end
   (images in prose, YouTube, link cards, SVG, file cards) plus the composer attachment pipeline
   (T12 `sendWithAttachments` + the missing PaseoKit binary-frame upload), because handing the
   agent pictures and files is table stakes for daily use.
4. **M7 — Search, history & command center.** Build the timeline search UI on the T12 store, the
   Sessions/History screen (date groups, search, load more) and the ⌘K/Ctrl+K command center —
   the three daily-driver surfaces, all unblocked and all missing today.
5. **M8 — Composer & turn parity.** Bring the typing surface to reference parity — queue +
   send-now/steer/interrupt, @-files and slash autocomplete, persisted drafts, context-window
   meter, fork/rewind, per-message copy, question-form cards, turn collapse levels — because the
   composer is where the hours go.
6. **M9 — Voice & the mascot.** Dictation first, then full voice mode (host Voice settings, speech
   provider sheets, keep-awake), and finally render the T13 mascot state machine on the chat page
   with the crab sheets — personality last, once the functional spine is done.
