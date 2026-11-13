# Status and handoff

Last updated 2026-11-12. Read `ARCHITECTURE.md` and `AGENTS.md` first. Work happens on branch
`foundation` (pushed to origin); `main` is untouched.

## Next session starts here (2026-11-11)

**L-round (upstream-first fixes, 2026-11-13) MERGED:** rule R-7 in AGENTS.md; tickets `docs/tickets/_L-common.md`, L1–L4; workers were Haiku 4.5 in worktrees under `/home/paseo/dev/l-round/`. L1: Retract/Delete turn/Edit/Rerun removed (upstream has none), rewind matches upstream (copy, composer restore, lock, refetch). L2: one host per daemon (relay+direct merge, `ConnectionSelection` port; runtime probing/switching NOT wired yet). L3: `ConnectionError` readable + `outcomeUnknown`, create-agent idempotency fields (not wired), focused-terminal heartbeat state (UI hookup missing), capability audit table (advertised set unchanged: pinned test). L4: docs corrected. Audit that drove it: `/home/paseo/dev/docs-audit/findings/` (FINDINGS, LEDGER, LEDGER-EXTRA, REVIEW). Gate green, PaseoCore 1008+214+164. IPA `Paseo-20261113-0748-49f8010.ipa`. Next (not started): L5 runtime connection switching; L6 session store (turn state from events not snapshots X-001, unknown-outcome send X-006, honest archive/permission answers, create via agent.create.request); capability advertisement (timeline_replacement_invalidation, timeline_notifications, workspace_setup_blocked) needs the pinned test `OwnedSubscriptionsCapabilityTests` updated; terminal focus UI hookup; build-gate v3 install on the Mac (simulator verbs) then UI tests.

**J-round MERGED (2026-11-12, device feedback 4 on IPA cacde34).** Tickets `docs/tickets/J1–J3` + `_J-common.md`; three pi DeepSeek v4.1 flash workers (thinking minimal), lead-traced root causes. J1: real Newsreader faces for bold/italic/headings (`ProseFaceTable`), Mermaid runtime lookup falls back to flat bundle name. J2: image-only paragraphs → gallery, file-link lines → media/file cards, bare URLs linked, list YouTube players after the list, `98.5` no longer a file link. J3: paste tile overlay framed (no giant circle), back-to-end button moved to a transcript overlay (hit-testable), decision uses keyboard-free content distance (`BackToEndState` in Core). Gates green; PaseoCore 974+208+145. IPA `Paseo-20261111-2243-2adbc1c.ipa`. Found, not fixed: Anthropic sans is one static face (~205 non-regular weight sites are no-ops; left as is), AnsiText perf test flaky under load, J3 header `roomBelow` still inset-based (no visible effect). Showcase chat: throwaway repo `/home/paseo/dev/paseo-showcase` + agent 61e2b3cf (pi beam-free) — archive/delete when the user is done.

**G-round COMPLETE (2026-11-12) (launched 2026-11-11, after the H-round).** Contract: `docs/tickets/G-rich-ui.md`

**2026-11-11 Phase A review:** report in (c4c0377, fff269b, decc50a). Gate FAILED (~25 compile errors). Review found: per-byte AsyncBytes work (actor hop per byte), relay rule applied to remote web images, daemon cap applied after transfer, disk-cache key mismatch/staleness, singleton daemon-fetch hook, dismiss pan steals paging, zoom relayout, preferredColorScheme in cover, NSCache cost, cap vs shared flight. Fixed over 3 rounds (+1 lead isolation fix). **Phase A MERGED** into foundation; gate green; PaseoCore green; IPA `Paseo-20261111-1531-b49ebb2.ipa`. Worker told: continue to Phase B (G4 Mermaid + G5 artifact page), stop and report.

**2026-11-12 Phase B part 1 (G4 Mermaid + G5 artifact page) MERGED** (fd98bac). Review: chat full-HTML artifacts were online (now WKContentRuleList + always-injected CSP), mermaid runtime loaded once in the shared offscreen host (no extra web view/window), generation-guarded timeout, SVG cache for the live page. Gate green, PaseoCore 835+208+145 green. Worker told: continue to the rest of Phase B (G6, G8, G9, G7, G10, G11, G12, G13), stop and report. IPA after Phase B.

**2026-11-12 Phase B part 2 (G6–G12) in review** (G13 not started). Gate FAILED (~14 errors). Review sent in 2 batches: media index never sees the streaming turn; change summary re-parses diffs per token; cache reads in .task cause remount flashes/jumps (link hero, gallery, terminal, YouTube title); 64 MB Data.write on main (video/file); remote audio bypasses pipeline; oEmbed/PDF/poster ignore §12; openDiff ignores the turn; GitHub lookup task never attached; gallery a11y collapsed; audio scrub steals scrolls; Now Playing without handlers; session left in .playback. Fixed; 3 lead compile fixes. **MERGED** (gate green, PaseoCore 889+208+145). IPA `Paseo-20261111-1855-3e8a7a6.ipa`; worker on G13 (charts), then Phase C.

**2026-11-12 G13 MERGED — Phase B complete.** Per-turn usage/cost charts: usage attributed by time (turn_started→next turn_started), cumulative figures as per-turn deltas with a frozen baseline (provider table in ConversationContext.swift). PaseoCore 900+208+145 green. IPA `Paseo-20261111-1915-fc2f8e3.ipa`. Worker sent to Phase C.

**2026-11-12 Phase C MERGED** (wide tables w/ content-versioned measure, todo/plan card, permission previews + D8 confirmed-only lines, subagent cards via mirrored map, user-bubble images w/ ratio manifest). PaseoCore 912+208+145 green. Worker sent to Phase D (G16 intents/Spotlight, G19 Allow/Deny off by default, §11 notification thumbnails).

**2026-11-12 Phase D MERGED.** App Shortcuts (Open agent / New agent, never sends), Spotlight titles, Settings → Privacy "Show agent names" (off by default → notifications read "Paseo / An agent needs your attention"), notification Allow/Deny (off by default, auth-required, sent from the delegate with a background task + ~8 s confirmation wait, else "Open" fallback; never switches host), cached-only notification thumbnails. No entitlements/App Group/extensions. PaseoCore 923+208+145 green. IPA `Paseo-20261111-2032-47cc1f4.ipa`; worker sent to Phase E (built, not embedded).

**2026-11-12 Phase E MERGED — G-round COMPLETE.** GlanceSnapshot (Core, tests) + throttled writer (no-op without App Group). `PaseoWidgets` extension target (small/medium/accessory widgets, 2 Controls) built but NOT embedded (pbxproj verified: no dependency, no embed phase); widget scheme not compiled by the gate (gate builds the app scheme only). Turn-on: paid team → App Group `group.com.wiselfx.paseoclient` → add PaseoWidgets to the app target's dependencies in project.yml + regenerate → App Groups capability on the app. PaseoCore 926+208+145 green. Final IPA `Paseo-20261111-2044-cacde34.ipa`. Worker 3d870bb3 idle with context. Open: device feedback on IPAs; G17/Live Activity/Share/Expo/G22 deferred; G23 doc.

(the rich UI plan made coherent; decisions D1–D8 taken by the lead on the user's delegation:
Mermaid bundled, Live Activity / Share ext / Expo deferred, extensions built but not embedded,
notification Allow/Deny off by default, §15 copy approved with upstream-first, permission line only
after daemon confirmation; H-round new copy approved). ONE worker: Muse Spark 1.3 contributor on Pi
(thinking high), agent `3d870bb3-a496-4dbe-a6e1-a7f28f0f7e29`, worktree
`/home/paseo/.paseo/worktrees/0264elgj/g-rich-ui`, branch `g-rich-ui`.
**Lead loop (repeat per phase A→B(G4+G5)→B(rest)→C→D→E):** on its stop report → read the FULL diff
against `G-rich-ui.md` §0 (mission-critical) → send exact fixes back to the same agent → push the
branch, merge into `merge-check` off foundation, gate build → ff foundation, PaseoCore tests →
reply "continue to <next phase>". Add a scorecard row per phase. Build an IPA after Phase A and
after Phase B. Known worker traps to check every round: `G-rich-ui.md` §4.


**H-round MERGED (2026-11-11): device feedback 3, all 10 bugs + bug-hunt fixes.** Code head
`ffd4db6`, Mac gate green, PaseoCore 1171 green. **IPA for the user:
`/Users/Shared/Paseo-ipas/Paseo-20261111-1403-ffd4db6.ipa`.** Tickets `docs/tickets/_H-common.md`,
`H1`–`H5`. Workers (Pi + DeepSeek v4.1 flash, idle, context intact): H1 `83e3f858`, H2 `b48fd6aa`,
H3 `25bbd6b1`, H4 `5c57d3e9`, H5 `8ff4267e`; bug hunter Muse Spark 1.3 (pi) `c1aee993`
(worktree `h-bughunt`). Upstream reference = `/home/paseo/dev/paseo-upstream-ref` (read-only,
v0.16.0-beta.1); the lab is off-limits.
- H1 voice: root cause `int16ChannelData` copied the channel-pointer array (heap addresses) to the
  daemon; UIKit display-link meter; start/stop lifecycle; category leak. Live wire proof via
  `paseo-probe voice` (refuses claude agents). Playback only verifiable on device.
- H2: runway only shrinks (PaseoCore `TranscriptChromeState`), back-to-end on the stable viewport,
  focus no longer yanks from history, auto-hiding sans header with a constant bar height.
- H3: context meter always in its slot (own Equatable view); expand control in the card corner,
  tallness from the field's own layout (lead fix: never touch `layoutManager`, keeps TextKit 2);
  picked files read off main.
- H4: splash = canvas + hero; appearance via window `overrideUserInterfaceStyle`; usage footer
  extracted, state-driven loads; launch-screen colour.
- H5: shared `RemoteImageLoader` (cache, UA, downsample, SVG, honest failures, boxed failure
  height); inline images tappable; YouTube stills.
- HB: permission-card timeout, schedules poll, file overwrite loop, provider save errors, Go key,
  schedule load error.
**Pending with the user:** device test of this IPA; approval of new copy (H5 failure strings, H4
Settings footer clause + 2 VoiceOver hints, HB file-version message). Open from reports:
`ChatController.outlineItems` rebuilt per read (move to store); optimistic permission line vs an
amnesiac store (decision); 6 pre-existing style-lint hits in Prose.

**Blocked on the user before writing G tickets** (doc 14 §5, "One decision message"):
1. IPA signing: free or paid team (gates G14–G21: widgets, extensions, Live Activity).
2. Bundle the Mermaid runtime, ≈3.5 MB (recommend yes; needs an existing test changed, so the
   user must approve that too).
3. Live Activity only if the G17 spike proves it stays truthful (recommend yes).
4. Allow/Deny actions on notifications (recommend yes, off by default).
5. Share extension (recommend later, after widgets).
6. Pay for push via Expo?
7. Approve the new copy listed there.

**Next round's workers use Pi**, not OMP: `pi` provider, model `opencode-go/deepseek-v4.1-flash`,
so the user can compare harnesses. Add a row per ticket to `docs/agents/scorecard.md` after each
review (judge items on their merits, not only on whether they were assigned).

**Idle E-round workers (OMP, context intact, reusable via `send_agent_prompt`):**
E1 `ffb609f4-27f6-4058-ba23-8622f70f4bd3`, E2 `a217e056-e061-4c11-b4ac-c48ce8ad5459`,
E3 `fb9b2c5e-6b6c-44eb-a03c-527616372ea7`.

**Known gaps (not yet fixed or not verifiable here)**
- Voice mode: needs the user's device run; logs are under `os.Logger` category `voice` /
  `voice.level`.
- Back-to-end button: it is an overlay on the bottom bar that extends above the bar's frame;
  hit-testing outside that frame is unverified on device.
- Rewind doesn't show for OpenCode because the live daemon reports no rewind capability
  (correct gating, not a bug). "Fork in a new workspace" is hidden without `workspaceMultiplicity`.
- File preview scheme (`paseo-file://`) ignores `Range` requests; multi-directory workspaces 404 on
  sibling paths.
- Composer card height ≈95 pt vs Claude's ≈98.7.

**Rules that bite (also in memory)**
- Never send to, prompt, create or probe any `claude`-provider agent. Live tests: `pi` +
  `opencode-go/beam-free`.
- Read every worker diff in full against `_E-common.md`'s mission-critical rules before the gate
  and before merging. A summary plus a green build is not a review.
- Mac gate: push the branch first, then
  `ssh -i ~/.ssh/paseo_build_ed25519 -o BatchMode=yes claude@host.orb.internal build|ipa <ref>`.
- Screenshots in `/home/paseo/dev/e-round-shots/` are private: never commit them.

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

## E-round (device feedback 2, 2026-11-11): read this first

The user tested IPA 3b65c9d next to the official Claude app and chose native over the React Native experiment (the lab is closed). Tickets: `docs/tickets/_E-common.md`, `E1`–`E3`. The workers are DeepSeek v4.1 flash on OMP (`omp/opencode-go/deepseek-v4.1-flash`, mode full, thinking high). The hard rule: no worker ever touches a `claude`-provider agent; live tests use `pi` with `opencode-go/beam-free`.

- **Merged on `foundation` (da8b549), Mac gate green, PaseoCore 1104 tests green:**
  - **E1:** the composer keeps the keyboard (a dead `@FocusState` → a plain Bool + an edge-triggered bridge); the waveform redraws per tick, fills the row, uses dB bands per mode; voice mode gets AEC (`setVoiceProcessingEnabled`), 16 kHz, a primed converter and `VoiceLog`; composer metrics match Claude.
  - **E2:** no scrim, a card shadow; the Claude/Paseo accent trait plus a setting; one launch screen (`HomeHeroLayout`); the connect card; the panel canvas; the prompt rail off (`ChatOutlineRail.promptRailEnabled`).
  - **E3:** harness subagents (the client now advertises `projected_subagent_timeline`); per-provider turn actions (`TurnActionAvailability`); SVG snapshots; viz card height; file HTML with JS; inline YouTube; viewer zoom; the probe's `--send` gate.
- **In flight, on new branches from foundation (the same agents):**
  - **E1b** (ffb609f4): the upstream AEC warm-up mic discard.
  - **E2b** (a217e056):
    - the greeting and rise once per launch;
    - DraftChatView adopts `HomeHeroLayout`;
    - the terminal tab and SwiftTerm background → panel;
    - the subagent running state → accent;
    - the panel shadow → leading offset;
    - shadow opacity constant while displaced (it was not animatable in the animator);
    - back-to-end attached to the composer (keyboard double-count);
    - sentence-case sidebar headers;
    - collapsed group rows ≈50 pt;
    - the Files header.
  - **E3b** (fb9b2c5e): the isolation warnings and `UIScreen.main`; a `paseo-file://` scheme handler for relative HTML refs; `unsafe-eval` for file previews only; subagent timeline paging; the viewer strip → panel.
- **E1b, E2b and E3b merged.** Every diff was read in full, E3b took 3 review rounds, and the lead fixed 2 things at the E2b merge (back-to-end clears the subagent pill; the terminal background is keyed by scheme). Mac gate green; PaseoCore 1114 green. **IPA for the user: `/Users/Shared/Paseo-ipas/Paseo-20261111-0955-5584843.ipa`** (the da8b549 IPA is obsolete).
- **UX plan:** `docs/research/14-rich-ui-plan.md` (trimmed) and `-full.md` (plus the lead's §8–15). The user's decisions are pending (§5 of the plan): signing, Mermaid bundle, notification actions, Share extension, Expo push.

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

IN FLIGHT: LongCat (pi, agent 347365b7-2f9e-4142-ae40-371aef3d6d4a) overall-performance investigation, read-only, report -> /tmp/reviews/overall-perf.md (+ drawer-lag-2.md); next: turn its ticket batches into P5.. tickets. Device feedback on IPA d2d6bdd (left sidebar restored, still laggy drawers, scroll better). Free opencode-provider models are out of quota; use pi/opencode-go/longcat-2.5-free; DeepSeek peak = weekdays 01-04, 06-10 UTC. Fix 2026-11-10: P3 left the conversation card background outside the offset, which hid the left sidebar; open flags moved to a reference box. P4 merged (incremental turn building: streaming rebuilds only the tail turn, ~14x on a 5k-row chat; tests 696/200/145 = 1041). Idle workers: DeepSeek aa2f0c45 (chat, u3-chat worktree), DeepSeek 165363ff (u2-new-session worktree). B2 archived workspaces dropped (2026-11-09 check): the daemon only exposes `listActive()`, upstream itself cannot list archives (only the undo toast + recovery by id), and DSH's Archived switch is over conversations, which our History already covers. Candidates next: device feedback on V1–V5 + P3, P3 leftover: incremental streaming Markdown parse.
**Perf round 2 (2026-11-10):** LongCat audit (`docs/perf/overall-perf.md`) -> P5-A streaming coalescing, P5-B prose caches, P5-C sidebar, P5-D panel unmount, P6-F chat view + rail glide-lead/landing line + prompt-rail touch-state fix, all merged, Mac build green, NOT device-verified. Open from the audit: batches E (diffs), G (shell/drawer), H (rich/WKWebView), I, J. Experimental branch `ocu-ui` (4 revertible commits from `docs/perf/ocu-spec.md`; user decides per group at home; no IPA until the user is home). Unfixed: user bubble 14 pt vs 17 pt (user's call). Idle LongCat/DeepSeek workers: p5-a..d, p6-f, ocu-ui worktrees. 

**Ready to test at home (built 2026-11-10):** two unsigned IPAs in `/Users/Shared/Paseo-ipas/` on the Mac.
- `Paseo-20261110-0541-991c7c5.ipa` = **foundation** (the whole R-round, current values), home-screen name "Paseo".
- `Paseo-20261110-0543-2289c7f.ipa` = **ocu-ui-2** (foundation + OCU values winning, 4 revertible commits: spec conflicts, motion, shape, palette), home-screen name "Paseo OCU".
Same bundle ID, so installing one replaces the other. Compare in light and dark, keep or drop each OCU group, then run the PLAN §4 checklist. Not ported from `ocu-ui`: the old sheet-header sizes (native SheetScaffold since R4) and the 36→44 visual button sizes (R11 already gives 44 pt hit areas with 36 pt visuals). Added beyond `ocu-ui`: the OCU sidebar colour is actually wired (on `ocu-ui` the token was unused).

**R-round (refactor + polish, 2026-11-10):** plan `docs/refactor/PLAN.md` (user approved decisions 1–6; OCU values deferred), audits `docs/refactor/audits/`, tickets `docs/tickets/R1..R11` + `_R-common.md`. Order: R1 moves → R2 tokens ∥ R3 core (all three merged, foundation a9d1a76 gate green) → R4 components (merged 785e1c9) → R5 shell, R6 conversation, R7 workspace, R10 sidebar (merged) → R9 prose, R8 settings (merged) → R11 sweep (merged; whole R-round done, Mac build green, NOT device-verified; next: PLAN §4 device checklist, then OCU re-applied as ocu-ui-2 for a side-by-side). Lead gate-builds every branch and sends compiler errors back to the same worker.

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

## D-round (device feedback, 2026-11-10 evening)

The user picked the OCU look; it is merged on foundation (`cffc95e`, display name back to "Paseo").
They tested it on device and reported problems. Tickets: `docs/tickets/_D-common.md` and D1–D4. Workers are DeepSeek, one worktree each under `~/.paseo/worktrees/0264elgj/`:

| Ticket | Branch | Agent |
|---|---|---|
| D1 header/scroll chrome, send scrolls to your message, bottom-jump fix | `d1-chrome` | 78c4600a |
| D2 Claude-style composer, image paste (multi), live voice meters, draft-send crash (P0) | `d2-composer` | 331a6f4c |
| D3 sidebar width, Settings chevrons, turn-detail fonts (R2 serif→title bug), compact k numbers | `d3-layout` | b92d04cb |
| D4 terminal smoothness (upstream docs/terminal-*.md), agent paging (65 vs 72 subagents) | `d4-terminal` | faf08a0b |

**D1–D4 merged** (foundation 4e2bf1b). IPA `Paseo-20261110-1142-4e2bf1b.ipa`; device testing pending. Lead fixes during the merge:
- D2's item-provider load is bridged through a continuation;
- D2's queue closure has an explicit type.

Unverified on device:
- whether `safeAreaBar` insets reach the transcript `ScrollView`;
- the send runway formula;
- the paste overrides;
- the voice meters.

D5 haptics merged: selection() 213→84, light() 1→47, success() is now a soft tap and fires only on awaited completions.
Notes from the D5 planning: Today there are 212 `selection()` calls and 34 `success()` notification buzzes. Plan: none on plain navigation taps, copy gets a light tick rather than success, and success is kept for awaited completions only.
Waiting on the user: the device crash log for the draft-send crash.
