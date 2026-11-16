# N3: chrome follow-up (solid top, no composer blur, keyboard gap, clock icon, tap-to-close, cleanups, upstream wording)

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (rules, proof, commit format), then `docs/tickets/N1-chat-chrome-and-drawer.md`
(what the previous round changed). Items A to F are direct user instructions (no upstream equivalent; write
`Upstream: none (user directive)`). Items G and H are upstream-first.

The lead looks at every item on a simulator afterwards, so implement exactly what is written and put anything
uncertain in "Found, not fixed" instead of improvising.

## Owns (touch only these)
`Conversation/Screen/ChatScreen.swift`, `Conversation/Screen/ChatHeader.swift`, `Conversation/Composer/ChatComposer.swift`,
`Conversation/Turn/*` (only for item D), `DesignSystem/Metrics.swift`, `DesignSystem/ClaudeStyle.swift`,
`Shell/ShellContainer.swift`, `Shell/EdgeDrawer.swift`, `Shell/ShellView.swift`, `Draft/DraftChatView.swift`,
`Workspace/WorkspaceChangesView.swift`, `Workspace/WorkspaceChangesDiffView.swift`, `Conversation/Turn/ClaudeToolDetail.swift`
(all under `Packages/PaseoUI/Sources/PaseoUI/`). New test files only; never edit an existing test.

## A. The top of the chat is still translucent; it must be solid
After N1 the top band under the status bar still lets scrolled text show faintly through it (a straight cut,
translucent instead of opaque). N1 set `Palette.background` behind `ChatTopChrome` and `.scrollEdgeEffectStyle(.hard, for: .top)`.
Something else still draws a material. Find it: in `ChatScreen.swift` the top bar is `.safeAreaBar(edge: .top) { topChrome }`
(iOS 26): read what `safeAreaBar` adds; look for `.glassEffect`, `.background(.ultraThinMaterial)`, `.regularMaterial`,
`scrollEdgeEffectHidden`, `toolbarBackground`, or any `.opacity(` on the header/backdrop in `ChatHeader.swift`
and the `TranscriptChrome*` helpers (`grep -rn "ultraThin\|Material\|glassEffect\|scrollEdgeEffect" Packages/PaseoUI/Sources/PaseoUI/Conversation`).
Also check the backdrop itself: `ChatTopChrome` fades the header out when it hides on scroll
(`.opacity(hidden ? 0 : 1)`); when the header is hidden the solid fill must still cover the status bar area
(move the solid `Palette.background.ignoresSafeArea(edges: .top)` out of the part that fades, keep only the
buttons and pill fading). Goal: at every scroll position nothing is readable through the band behind the
clock and the header.

## B. Remove the blur above the composer
There is a soft fade/blur band above the composer (content dissolves into it). Wanted: none; the transcript is
cut cleanly where the composer card starts. In `ChatScreen.swift` the bottom edge uses
`.scrollEdgeEffectStyle(.soft, for: .bottom)`: change it to `.hard`. Then grep the bottom bar content
(`bottomChrome`, `ComposerView`, `composerCardChrome`, `SubagentPill`) for any material, gradient or blur
behind the composer and remove it. The composer card itself keeps its own fill and border.

## C. Gap between the composer and the keyboard: 8 pt
Measured on the user's Claude app screenshot (3x): the composer card's bottom edge is 24 px = **8 pt** above the
keyboard. Measured on ours: about 1 pt (nearly touching). Make the visible gap between the composer card and the
top of the keyboard **8 pt** while the keyboard is up; when the keyboard is down keep the current bottom spacing
(home indicator). Find where the composer's bottom padding is decided (`ComposerView` / `composerCardChrome` in
`ChatComposer.swift`, and `bottomChrome` in `ChatScreen.swift`), use a `Space` token for 8 (grep `Space.` for
the token that equals 8; if none, `Space.sm` if it is 8, else report which tokens exist). Do not add per-frame
keyboard arithmetic: use padding that follows the safe area the bar already follows.

## D. A clock icon in front of "Completed in X"
`DesignSystem/ClaudeStyle.swift` has `DurationText.completed(_:)` ("Completed in 4s"). Find where the row that shows
it is built (`grep -rn "DurationText.completed" Packages/PaseoUI/Sources`). Put a clock icon before the text:
`Image(systemName: "clock")`, same colour and size as the row's text, `.accessibilityHidden(true)` (the text already
says it), with `Space.xs` between icon and text. Look at how the reasoning row ("Deciding how to respond...",
`grep -rn "Thinking\|reasoning" Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn`) draws its leading icon and copy
its size, weight and colour. Use only SF Symbol names already used in the repo (`clock` is used in
`Schedules/ScheduleDetailPage.swift:96`).

## E. Tapping the chat closes the sidebar again
`ShellContainer.swift` keeps a `dimView` as "the tap-to-close target with zero alpha", but UIKit skips hit-testing for
views with alpha below 0.01, so the tap never arrives (`EdgeDrawer.scrimOpacity` returns 0 and `applyModel` writes it
to `dimView.alpha`). Fix: the dim view must be hit-testable while a surface is on screen but still draw nothing.
Give `dimView` a clear background and set its alpha to 1 when `max(s, p) > 0` and to 0 otherwise (keep
`isUserInteractionEnabled` consistent with that); do not draw a scrim. Read how the dim view's tap recogniser
closes the surface and make sure a tap on the pushed-aside chat closes the sidebar, and that the hamburger button
(N1) still works. Keep animations as they are.

## F. The new-session screen's hamburger has the same open-only bug
`Draft/DraftChatView.swift` ~line 57-66: its sidebar button only opens. Make it toggle exactly as N1 did for the chat header
(`@Environment(\.shellDrawer)` and `drawer.toggle(.sidebar)`; read `Conversation/Screen/ChatHeader.swift` `toggleSidebar(open:)` and
copy the pattern). Also `Shell/ShellView.swift` lines ~170, 181, 185, 199: the shell's own sidebar closures
are open-only; make them toggles the same way if they are reachable from a visible button, otherwise leave them and say so.

## G. Delete what is unused
`Metrics.swift` `TranscriptHeader.backdropOpacity` and `TranscriptHeader.backdropFadeLocation` have no users after N1.
Confirm with `grep -rn` (including `Packages/PaseoUI/Tests`; if a test pins them, STOP and report, do not edit the
test) and delete them with their doc comments. Do the same check for anything else N1 and this ticket leave unused in
your owned files and delete it.

## H. Upstream wording and whitespace behaviour
1. `Workspace/WorkspaceChangesView.swift` ~lines 797-798 say "Hide whitespace changes"; upstream says "Hide whitespace"
   (`/home/paseo/dev/paseo-upstream-ref/packages/app/src/git/diff-pane.tsx:842-844`, strings in
   `packages/app/src/i18n/resources/en.ts` ~983-986: "Hide whitespace", "Show whitespace", "Wrap long lines",
   "Scroll long lines"). Use the upstream strings verbatim everywhere our diff menus show these options.
2. Behaviour: upstream does not filter lines on the client; it asks the daemon for a whitespace-ignoring diff
   (`diff-pane.tsx:452`, `hideWhitespace: input.hideWhitespace`). Our workspace Changes screen already does that
   (`ignoreWhitespace: hideWhitespace`). The chat diff sheet (`ClaudeDiffView` in `Conversation/Turn/ClaudeToolDetail.swift`)
   filters adjacent removed/added line pairs on the client because its diff comes from the tool call. Find out whether
   the daemon can return a whitespace-ignoring diff for that file from the same call the workspace screen uses
   (`grep -rn "ignoreWhitespace" Packages`). If it can, make the chat sheet use it when "Hide whitespace" is on and
   delete the client-side filter (`ClaudeDiffLine.hidingWhitespaceOnly`); if it cannot (the file may not be in the
   checkout any more), keep the client filter and say exactly why in the final message. Do not guess: read the code.

## Proof
`swiftc -parse` every edited file. `Tools/style-lint/style-lint.sh` on your files: no new hits. Commit as
`N3: solid top, no composer blur, 8 pt keyboard gap, clock icon, tap to close, cleanups, upstream wording`, body listing
the upstream citations for G/H.

## Final message
Per item A to H: what you changed (file:line) or why you did not; every Apple API or token you were unsure of;
and "Found, not fixed".
