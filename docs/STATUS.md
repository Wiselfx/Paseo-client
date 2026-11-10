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

U-round: the first on-device fix round (2026-11-09). Spec: `docs/UX-SPEC.md`. Audits: `/tmp/reviews/ux-audit-{A,B}.md` (Crouton). Fixed directly by the lead: the send wipe (dictation.stop emitted an empty draft) and the dictation off-main crash.

| Ticket | Branch | Worker | What |
| --- | --- | --- | --- |
| U1 | merged | DeepSeek | Full-bleed shell (the clip cut backgrounds to the safe area), constant 55 pt corners, hairline edge + dim, one `.smooth` settle, full-width panel push, sidebar footer pill, badge removal |
| U2 | merged | DeepSeek | `DraftSession` (PaseoStore, 12 tests), `DraftChatView`, `DraftControlsSheet`; New Agent sheet deleted; dynamic composer; DSH mark |
| U3 | merged | DeepSeek | Auto history with an anchored prepend (lead fix: re-apply only on growth), full turn nav, translucent rail, full messages, bubble menu, mascot seeding, subagents capability wire fix (`provider_subagents`), thinking list, SVG/HTML |
| U4 | merged | Crouton | PaseoFormat, CronDescription (11 tests), monochrome, toggle tint, file sizes, search header. Lead fixes: bytes hand-rolled (ByteCountFormatter has no locale); identifiers ungrouped |

Tests: PaseoCore 683/200/145 green (1028).

**Mac build gate (2026-11-09):** `ssh -i ~/.ssh/paseo_build_ed25519 claude@host.orb.internal build <pushed ref>` compiles the real app (iOS Simulator, signing off). Every merge is now compiled before the user pulls. Gate source `Tools/build-gate/build-gate`; the installed copy on the Mac changes only when the user re-copies it.

**V-round (parity, from `/tmp/reviews/parity-sweep-2026-11-09.md`):** V1 chat actions (fork tab/workspace, in-flight fork, DSH Retract/Delete turn, compaction marker), V2 detach subagent + managed-subagents section + branch switcher, V3 test notification + service-URL setting + PR check Add to chat. All merged, Mac build green. Not ticketed (drop unless asked): DSH bar/caret, language, split settings, DSH mascots/ripple, plugins/catalog, config.apply bundle. Blocked: APNs push (needs server). V4 (host idle/restart cards, dictation overlay + AVAudioSession off main, provider SVG glyphs) and V5 (17 pt chat text, tap-to-dismiss keyboard, composer height cap 40%, always-card composer in conversations; UX-SPEC §4.1 updated) merged at d78a2d9, Mac build green.

**Merged:** P3 performance pass (275aee1, Mac build green): drawer progress isolated from the shell body, draft observer, prose markdown/linkify memo, scroll-track box, decorated sorts, mascot stops when asleep, cached NumberFormatters, TimelineView(.animation) uncapped. Audit `/tmp/reviews/perf-audit.md`. Left: streaming incremental parse, TurnBuilder full rebuild per delta, panel kept mounted (SwiftTerm alive). Needs a device feel check.

**Gate `ipa <ref>` verb** added (65ec8de) → `/Users/Shared/Paseo-ipas/`; works once the user re-copies the gate (asked 2026-11-09). After each merged batch, run it so the user can test.

P4 merged (incremental turn building: streaming rebuilds only the tail turn, ~14x on a 5k-row chat; tests 696/200/145 = 1041). Idle workers: DeepSeek aa2f0c45 (chat, u3-chat worktree), DeepSeek 165363ff (u2-new-session worktree). B2 archived workspaces dropped (2026-11-09 check): the daemon only exposes `listActive()`, upstream itself cannot list archives (only the undo toast + recovery by id), and DSH's Archived switch is over conversations, which our History already covers. Candidates next: device feedback on V1–V5 + P3, P3 leftover: incremental streaming Markdown parse.

**Merged:** U5 prompt outline (`docs/tickets/U5-outline.md`): daemon prompt index (`agent.timeline.list_prompts`), window jump with `mergeWindow`, tick rail with no reserved margin, picker-wheel haptics. `loadAllOlder` removed. Lead change at merge: the hidden rail is not hit-testable. Known gap: in the loaded-turns fallback (no index) the active tick is not highlighted.
- Covers: upstream prompt index RPC + jump fetch, `loadAllOlder` removed, tick-only rail with no reserved margin, picker-wheel haptics.
- On finish: review, merge, then tell the user to pull.

**User feedback queue:** U2 needs a device check; real provider SVG glyphs (`iconSvg`) in the chip; Add provider (protocol shape first); the terminal "link" icon is still unidentified; the AVAudioSession `setActive` hang-risk fault.

Open: voice mode no longer crashes on the simulator (fresh pull); dictation on a device untested; AVAudioSession setActive on main (hang-risk fault); the terminal "link" icon (which button?), Add provider (needs a protocol patch shape; later ticket).

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
restart/view service, local links, 2k scrollback, M3h file sort/share/Markdown+image preview,
diff options (hunk-level whitespace hide, wrap, collapse) and jump-to-file, M8d @-file mention
popover (scratch WorkspaceFiles walk) + on-device dictation (Info.plist mic/speech keys), R10 split:
`Sidebar/` and `Schedules/` folders; restored a missing `sectionHeader` the Pinned section called
(swiftc -parse can't catch missing symbols: Xcode will) T16 flake fixed (test-side race) + context/usage store
(`contextUsage`, `session.hostUsage`; no UI yet) M3i PR pane (checks, review/comment timeline
from hand-written fixtures, Add to chat) + base-branch picker M8e context ring + sheet in the
composer, opt-in sidebar usage row + reports sheet, M7d chat anchor on send, per-chunk prose reveal,
Rewind to here (opencode: `both` only; the sandbox agent's tail was truncated at seq 36 by a rewind)
R11 split ClaudeChatView into
`Conversation/` (13 files, pure move), M2.10 setup line + sheet (polls
status; live push needs `owned_subscriptions`, not advertised) and worktree archive warning (dirty/
unpushed counts), M4d Providers sheet (diagnostic, custom models) + agent profiles CRUD (config patch
`agentProfiles`, gated) M7e History with archived agents
(fetch_agent_history paging), unarchive (refresh_agent_request), archive/delete/rename rows
M7f chat display (Full/Collapse
tool calls/Collapse turns), provider-subagents pill + sheet, DSH question card (PaseoCore
416/133/17 = 566 green). Store gap: background work (`agent.background_work.*`) has no wire/store (M7g).
M8f profile picker in the new-agent sheet (feature values sent on create)
M2.11 Project page (name, icon,
setup/teardown, scripts via paseo.json with revision check) R13 + lead cleanup removed ~3.6k
lines of dead ClaudeUI demo code (ClaudeAppearance now its own file), M7g background work
(gated: daemon 0.15.2 lacks it) + tappable file paths in chat (fixed M7f's subagent timeline wire
shape), M1b saved hosts (Keychain per host), TLS + advanced URI, footer host switcher, Settings →
Hosts; Info.plist mic/speech keys moved into project.yml (PaseoCore 445/135/17 = 597 green).
M2.12 workspace labels (+ M7e's
missing HostSession wiring), M9 Search row + command palette, M3j Save to Files/Reveal, Choose URL,
file into terminal, gh callout, side-by-side diff, M3i PR section now mounted, M4e About/Diagnostics
(scrubbed report)/Terminal/Sidebar pages M7h Edit/Rerun on your messages
(rewind-based), Fork from here (agent.fork_context + chat_history attachment), images in prose
(PaseoCore 473/139/17 = 629 green; PARITY 272 done / 77 missing of 421). M4f Pure black +
content/code size (font changes rebuild the tree via RootView `.id`: polish pass should move
typography into the environment; terminal font size not yet scaled). M2.13 sidebar: Active first (running float up), Group by Project/Date (Today/Yesterday/Earlier, not collapsible), worktree-setup callout via `ProjectSetupProbe` (PaseoCore 481/139/17 = 637 green; PARITY 277 done / 72 missing of 421). M2.14 manual unread + DSH date sections (collapsible;
Active/Archived switch dropped: the daemon hides archived workspaces and has no listing RPC), M3k diff
review comments + Send feedback (persisted drafts, review attachment), M7i turn rail (while scrolling) +
"Jump to message…", Faster↔Smarter effort ladder, hero workspace/profile seats, M4g welcome screen (no
saved host), Help & support page, Always expand reasoning (General → Chat), R14 API audit
(`Tools/api-audit/README.md`: run before merges; current findings are generic-parameter false
positives). PaseoCore 637 green; PARITY 288 done / 60 missing of 422. M10 local attention notifications
(AttentionCenter + NotificationCoordinator; live socket only, no remote push without a relay/APNs;
`docs/research/10`), PaseoCore 497/144/17 = 658 green. T18 (Crouton via pi): slash-command cache invalidates like
upstream (provider snapshot change, reconnect), host diagnostics (Settings → Diagnostics, scrubbed),
terminal font follows Code size; GitHub search has no stars on the wire (upstream schema). 665 green.
T17 owned subscriptions ON (modern socket: every push family re-acquired, re-subscribed on reconnect;
kill switch `OwnedSubscriptions.isEnabled`; contract `docs/research/09`; fixed agent attention +
`notifications: true` so M10 works in modern mode). Setup progress push verified live (sandbox worktree, running → completed). PaseoCore 524/144/20 = 688 green. M11 (Crouton): Import session (sidebar, panel Agents page,
command palette; per-provider recent sessions, search/workspace scope gated), terminal notification
tap opens that terminal, stale review drafts Clear line. PaseoCore 532/149/20 = 701 green; PARITY 295
done / 53 missing of 422. M12 (Crouton): Add issue or PR picker (forge.search, legacy fallback,
forge_issue/forge_change_request attachments), DSH sound cues (Off/Soft/Clear, synthesized, ambient
session), PARITY sweep. Lead fix: forge label uses `existingCheckout` (no store creation in body).
PaseoCore 536/155/20 = 711 green; PARITY 300 done / 48 missing. M14 (Crouton): usage overview in the
usage sheet (Swift Charts, DSH figures/books from agents' lastUsage: no token-history RPC) and a
reconnecting / can't-reach banner in the shell (lead: plain wording). M13 (Crouton): Settings → Host
→ Voice (dictation/voice-mode providers, OpenAI key write-only, local speech models with polled
download progress). Realtime voice mode not built (needs `voice` hello cap, PCM streaming, playback).
PaseoCore 548/166/20 = 734 green; PARITY 306 done / 43 missing of 422. M16 (Crouton): host badge
(>1 host, upstream identity colors), Connections page (the app's saved endpoints: no daemon RPC),
Danger zone Remove host (also fixes forgetting the current host). No provider install RPC exists.
PARITY 310 done / 39 missing. R16 (DeepSeek): relay crypto core in PaseoKit/Relay (Noise NK passes the
public cacophony vectors byte for byte, record codec with all rejection rules, offer/relay:// parsing,
protected mode only); swift-crypto added to PaseoKit (user-approved). PaseoCore 548/166/86 = 800 green.
M17 (Crouton): map cards (strict standalone coordinates / geo: / Maps URLs, MapKit snapshot), drag
Files/Changes rows into the composer (@path mention), cost bubble on long-press of the crab.
PaseoCore 559/166/86 = 811 green; PARITY 313 done / 36 missing.
P1 (DeepSeek): polish audit `docs/research/12-polish-audit.md` + low-risk fixes (upstream copy, adaptive
grays, 0.5 pt dividers, a11y labels/traits, 44 pt composer targets, Reduce Motion gaps, GitHub casing,
`#-1`). Its blue→orange/system→ClaudeTypography swaps in Settings were reverted (ClaudeUI pinned).
Proposals (header, ToastHost, 44 pt pass, Files toolbar) wait for the polish pass with the user.
Platform priority: iPhone first, then Mac; no iPad-only work (M18 dropped).
R17 (DeepSeek): relay transport (`RelayWebSocketTransport` wraps any socket; queued sends, stable hello
retries, 32 MiB wire bound, 4001 retry / 4002-4003 terminal, protected-only admission after
`server_info`), `RelayPinning` (pins + secret store protocols). PaseoCore 559/166/127 = 852 green.
M15 voice mode: Crouton built it, DeepSeek review found a crash + compile errors; DeepSeek 8872f024 rewrote
the audio engine (one explicit playback format, one-shot converters, capture DSP off main), lead added
@Sendable audio callbacks + AVAudioApplication permission. R19 Pair devices (QR on a white tile, copy
localOnly + 2 min expiry, enable relay behind relayConfig). PaseoCore 583/177/128 = 888 green;
PARITY 319 done / 30 missing. api-audit: `AVAudioConverter.convert` missing-member is a false positive.
R18 pairing UI (Crouton, two DeepSeek review rounds): Add host → Direct / Scan QR (VisionKit) / Paste link,
"Connect to this host?" confirmation with upstream fingerprint, password sheet (incl. rotated password on a
saved relay host), relay passwords in Keychain as `relay.<serverID>`, 1 MiB relay upload chunks.
M20 merged (`paseo://` scheme + `.onOpenURL`: offer links → R18 confirm sheet; agent/workspace/host/open-project routes switch host if needed; searchable host chooser; M20b: saved direct hosts remember the daemon serverId after a connect, so links match any saved host; duplicate direct+relay rows are detected (`duplicateDaemonServerIDs`) but not merged — UX decision pending with the user: merge / union routes / annotate + Forget / nothing). M19b merged (agent-to-agent messages render as user bubbles with "Sent by"). R17c merged (RelayConnectionTests harness now waits for the daemon to decrypt the hello before pushing; 23/400 → 0/400 under load). P2 merged (doc 13: fixed public `body` on the pairing sheets, public WelcomeView, Chart ids, file-row `.draggable`; Xcode-only suspects listed in doc 13). M19 merged (collapsed turns show upstream's summary line / "View turn details"; "Sent by" blocked: our timeline has no agent_message sender). R17b merged (relay close-code tests now await the close; 0/300 flakes under load). M15c merged: upstream thinking tone (bundled 16 kHz PCM blob, 1.5 s first delay, upstream repeat timing, own player node; also used by Diagnostics → Test audio). PaseoCore 632/177/144 = 953 green; PARITY 324 done / 25 missing. Relay track R15–R19 complete (needs Xcode).
Xcode: the new package needs File → Packages → Resolve/Reset Package Caches. Gap: host `diagnostics.request` has wire type only (needs a store slot). R12 synced PARITY.md: 242 done / 104 missing / 47 desktop-only / 7 store-only of 420 rows. Unsure-compile hot spots: M3g SwiftTerm APIs (inputAccessoryView key
bar, linkReporting/requestOpenLink, changeScrollback), M8c nested Features pages in ClaudeAgentControlsSheet.

Running. Inkling hit its free limit (2026-11-09 ~10:00 UTC): all workers now run on DeepSeek
in pi (`pi/opencode-go/deepseek-v4.1-flash`), off-peak only; reuse a worker for the same thread of
work, start fresh when scope changes or its context drifts (256k context, compactions degrade it).
Crouton (`pi/opencode-go/crouton-alpha-free`, thinking max) passed its trial (T18, M11): real tickets.
- Idle: DeepSeek 85844e34 (P1 polish context), DeepSeek 6db40c26 (R17; reviewer for R18).
Known store gaps: fork can't carry provider feature values.

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
