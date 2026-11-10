# Drawer lag, round 2 (focused) — superseded by `/tmp/reviews/overall-perf.md`

Read-only audit. No daemon contact, no code changes, no commits. Linux VM: no Instruments.
This file keeps the drawer-specific findings from the original task; the widened investigation
(overall smoothness, all screens) is in `/tmp/reviews/overall-perf.md`.

Context: P3 already moved the drawer progresses out of `PaseoShellView.body` into `ConversationCard` /
`PanelCard`, and stopped the open flags from invalidating the shell. So a finger move no longer
re-evaluates the sidebar/chat/panel. What remains is below. Line numbers are current HEAD (`d2d6bdd`).

## What is still expensive per frame of a drag / settle

1. **`ConversationCard.body` / `PanelCard.body` rebuild full-screen layers every frame.**
   `Chat/PaseoShellView.swift:567-650`. `.background { EdgeDrawerCard() }` is a full-bleed
   `RoundedRectangle(.continuous).fill(...).ignoresSafeArea()`; the overlays are a full-screen
   `EdgeDrawerDim` (`Color.black.opacity`, `.contentShape(.rect)`, `.onTapGesture`) and a 0.5 pt
   `EdgeDrawerHairline` stroke. The dim's opacity and the hairline's stroke opacity both change per
   frame, so both layers re-render. **Fix:** animate the values on one persistent layer instead of
   rebuilding the views; keep the dim as a single `RoundedRectangle` whose `opacity` is the animated
   value. **S/M**, confidence medium (guess).

2. **Up to five simultaneous `DragGesture`s over the scroll view.**
   `Chat/EdgeDrawer.swift:47-60`; attached at `Chat/PaseoShellView.swift:178-189` (two on the
   conversation surface), `:217-222` (panel card), and `Workspace/WorkspacePanel.swift:246-256`
   (header + agents/files pages). Every touch on the transcript/panel is offered to all of them plus
   the scroll view's pan; each armed drawer writes `@State progress` on every event. `directionDecided`
   only guards after the first event, so a vertical scroll still pays the first-event cost.
   **Fix:** one drawer gesture per surface with a computed edge; `.highPriorityGesture` for the edge
   zones; `.simultaneousGesture` only on an open surface; don't attach the second gesture when the
   panel is closed. **M**, confidence medium.

3. **Live animations inside the moving card never stop.**
   `Mascot/ClaudeCrabView.swift:196-200` (`TimelineView(.animation)` at display rate, even when the
   mascot is sleeping), `Chat/ClaudeStatusLine.swift:231-240` and
   `Conversation/ChatWorkGroup.swift:139-145` (masked text sweeps at display rate while a turn runs),
   `Sidebar/PaseoStatusDot.swift:18-22` (`.repeatForever` running dots). These keep the GPU/CPU busy
   during a drag. **Fix:** pause the crab and the sweeps while a drawer is open, or lower their rate;
   stop the crab's timeline when sleeping. **S/M**, confidence medium (guess).

4. **The settle animation animates `@State progress`, re-evaluating the card bodies ~120 times.**
   `Chat/PaseoShellView.swift:366-378`. Intended; only the offset/dim/hairline need to animate, and
   the card content is a stored value. If #1 is fixed this is cheap. **M**, confidence medium (guess).

5. **An `agent_update` mid-drag re-evaluates the shell body and the sidebar.**
   `PaseoShellView.swift:78-84` (body depends on `session.agents` via `.onChange(of:)`, `:104`),
   `Sidebar/PaseoSidebar.swift:79-84` (non-lazy), `Sidebar/SidebarDirectory.swift:228-252,406-420`
   (`activityDate` scans all agents, parses dates), `Sidebar/SidebarRoll.swift:15-23` (builds
   collapsed rows to measure them), `Sidebar/SidebarWorkspaceRow.swift:78,117-175` (`agents(in:)`
   per row, `activityDate` up to 3× per row). A store change lands in the middle of the gesture and
   rebuilds the sidebar. **Fix:** precompute `[workspaceId: agents]` + activity dates once per
   evaluation; `LazyVStack`; skip collapsed content. **M**, confidence medium-high.

6. **The transcript's scroll readout is O(turns) per frame and recreates a `Task` per frame.**
   `Conversation/ChatTranscript.swift:245-266,671-690`. This is why "transcript scrolling is smoother
   but not perfect" on a long chat. **Fix:** only recompute when the top visible row changes; throttle
   `revealTurnRail`; cache `outlineItems`. **S**, confidence medium (P3 left this).

7. **The moving card contains a `TextEditor`/`TextField` and a `ScrollView` + `LazyVStack`; the panel
   underneath stays mounted with live subscriptions.** `Workspace/WorkspacePanel.swift:123-140`
   (`.task` at shell creation), `WorkspaceTerminalsView.swift:67-70` (terminal attached),
   `WorkspaceChangesView.swift:115-125` (diff subscription). Off-screen work and re-renders continue
   during the drag. **Fix:** gate the panel's work on `progress > 0`; unmount the page when closed
   (keep the tab id); detach terminals/diff subscriptions. **M**, confidence high.

## What I did not verify

- I did not measure any of this on a device. The ranking is from reading the code and from the P3
  microbenchmarks; the per-frame magnitudes are guesses.
- The drawer lag has several independent plausible causes (#1–#5); I did not isolate which dominates.
  They are independent fixes and all worth doing.
