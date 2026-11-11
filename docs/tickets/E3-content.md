# E3: harness subagents load, per-provider actions, rich media that looks done

Branch `e3-content`, from `foundation`. Read `_E-common.md` first.

**Owns:**
- `Conversation/Sheets/ChatSubagents.swift`
- `Conversation/Screen/SubagentPill.swift`
- `Conversation/Screen/ChatController.swift` (subagent loading and turn actions only)
- `Conversation/Transcript/ChatTurns.swift` (turn action menus only)
- `Conversation/Prose/Rich/`
- `Conversation/Prose/ClaudeMediaView.swift`
- `Conversation/Prose/MediaState.swift`
- `Workspace/WorkspaceFileViewer.swift`
- `Workspace/WorkspaceFileWebDocument.swift`
- PaseoCore: `PaseoProtocol/Subagents.swift`, the subagent part of the store, plus new test
  files

## 1. Harness subagents don't load

These are the provider's **own** subagents (Claude Code's Task/Agent tool, OpenCode's and OMP's
native subagents), surfaced through `agent.provider_subagents.*`. Paseo-managed child agents are
not part of this item. Many of them open to nothing.

1. **Reproduce it live first.**
   - The daemon on this machine has real agents with harness subagents (look for Claude agents
     whose timeline has `Task`/`Agent` tool calls, and OMP agents).
   - Use `swift run paseo-probe` (add a subcommand if needed, in the probe only) to call
     `agent.provider_subagents.list.request` and `agent.provider_subagents.timeline.get.request`
     for them.
   - Capture the raw JSON for one that works and one that fails.
2. Find the failure. Candidates to check:
   - a decode error (a field the schema marks optional that we require, an unknown item type
     that fails the whole page instead of being skipped);
   - the wrong id (the tool-call id vs the subagent id);
   - a missing `cursor`/paging;
   - a missing handshake capability;
   - a request sent before the list arrived;
   - a timeline item kind we don't render.
   - Compare with the server schema
     (`/home/paseo/dev/paseo-reference/packages/server/src/shared/messages.ts`, search
     `ProviderSubagent`) and upstream's client.
3. Fix it. Decoding must be **lenient per item**: an unknown or malformed item becomes an
   "unsupported item" row, never a failed timeline.
4. **States:**
   - loading is the shared skeleton;
   - an empty timeline says so (upstream copy);
   - an error shows the error with "Try again" (upstream copy) instead of a blank sheet.
5. **Tests (new file):**
   - decode the captured fixtures, scrubbed of private text (see the fixture privacy rule:
     replace content strings);
   - an unknown item kind is skipped;
   - an empty timeline.

## 2. Turn actions match what each provider can actually do

- The user: "Claude Code has rewind and all, but Pi doesn't; I don't think OpenCode does either."
- Our assistant turns show copy, fork (Y) and delete (trash) under every provider, and the user
  bubble menu offers rewind.
- `rewindMenuScopes` (`ChatController.swift:278`) already gates rewind on
  `session.isRewindSupportedByHost` + `store.rewindCapabilities`. Fork and delete/retract don't
  appear to be gated.

**Build:**
1. Read upstream's gating:
   - `packages/app/src/components/rewind/use-rewind-capabilities.ts`;
   - `rewind-menu.tsx`;
   - `components/message.tsx`;
   - the fork and delete (retract) actions' conditions;
   - the agent capability flags in the server schema.
2. Gate **every** turn action (rewind, rewrite, fork here, fork to a workspace, delete/retract
   turn) on exactly the capability upstream uses. Make one `TurnActionAvailability` value,
   computed once per agent and capability change in the controller (not in row bodies), passed to
   rows as a value (R-2).
3. An action the provider can't perform is **not shown**. It isn't greyed out, and it doesn't fail
   after tapping.
4. In the final message, a table: action | the upstream condition (file:line) | Claude | Codex |
   OpenCode | Pi | OMP. Fill the provider columns from the capabilities the live daemon reports
   for an agent of each (probe).

## 3. Rich media looks done

The user: "SVGs in chat render in small windows; so does HTML probably. The Files panel HTML
doesn't render the main content. YouTube videos should play in chat, not take you to YouTube."

A separate UX research plan (`docs/research/14-rich-ui-plan.md`) will follow for the bigger
redesign. This item makes today's blocks correct and good.

1. **SVG.**
   - Render at its intrinsic aspect ratio (from `viewBox`, else `width`/`height`), at the full
     transcript width, capped at 60 % of the screen height. No inner scrolling, no tiny window,
     and no letterboxed WebView with blank space.
   - Rasterise off main or render in one `WKWebView` sized from the reported content size. Pick
     whichever gives crisp output without per-scroll work, and justify it.
   - Tap → full-screen viewer with pinch-zoom (reuse the image viewer if one exists).
2. **HTML cards in chat** (`SandboxedHTMLView`, ceilings 400/800 at `ClaudeRichBlocks.swift:722`).
   - The height follows the reported content height up to 70 % of the screen height, animated once
     when it settles (no repeated jumps while scripts lay out: debounce the height reports by
     100 ms and ignore changes < 2 pt).
   - Above the cap, show an "Open" affordance to a full-screen page (existing copy if any,
     otherwise "Open" is approved).
   - A web view inside the transcript must not steal vertical scroll: inner scrolling stays off
     while it fits.
3. **The Files panel HTML preview renders blank** because `allowsScripts` is false for file
   previews (`SandboxedHTMLView.swift:55`) and most real pages build their content with
   JavaScript.
   - Turn page JavaScript on for file previews, in a `WKWebsiteDataStore.nonPersistent()` store.
   - Top-level navigation away from the loaded document opens in an in-app Safari sheet
     (`SFSafariViewController`), never inside the preview.
   - Keep the CSP the document builder injects, but allow scripts and network subresources so CDN
     libraries load.
   - Relative file references (`./style.css`) can't resolve with `baseURL: nil`. List that as a
     known gap in your final message, with the shape a fix would need (daemon file reads); don't
     build it.
4. **YouTube plays in place.**
   - The card shows the thumbnail (as today) at 16:9, full width.
   - A tap swaps the thumbnail **in place** for an inline player: a `WKWebView` with
     `allowsInlineMediaPlayback = true` and `mediaTypesRequiringUserActionForPlayback = []`.
     - Load the `youtube-nocookie.com/embed/<id>?playsinline=1&autoplay=1` iframe inside a tiny
       HTML document whose `baseURL` is an `https://` origin. YouTube rejects embeds with no
       referrer (player error 152/153).
     - The swap is a `Motion.fade` crossfade, with no layout change (same 16:9 frame).
   - A small "Open in YouTube" in the card's context menu keeps the old path.
   - Only one inline player plays at a time; scrolling it far off screen pauses it.
   - The player's web view is created on tap only, never for every card in the transcript.
5. **Images, video and audio blocks** in `ClaudeMediaView`. Check them against the same bar, and
   fix what is clearly broken or ugly:
   - aspect ratio from the image, no layout jump on load: reserve the size from metadata when
     known, else animate once;
   - decoding off main;
   - a tap to full screen;
   - video inline with native controls (`AVPlayerViewController`);
   - audio as a compact player row.
   - List what you changed.

**Performance gate:**
- No `WKWebView` is created for a block that isn't on screen. Cards are lazy; the web view comes
  up when the card appears and is torn down (or pooled) when it goes far off screen.
- Scrolling a transcript of 20 rich cards must not build 20 web views.
- State the strategy in your final message.

## Proof

As in `_E-common.md`. Also:
- the raw-JSON root cause for §1;
- the §2 table;
- the §3 performance strategy.
