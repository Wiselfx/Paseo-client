# N1: chat top chrome (no blur, title pill), side panel width, sidebar button toggles

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (rules, proof, commit format), then this file.
These four changes are direct instructions from the user, so there is **no upstream equivalent**; write
`Upstream: none (user directive)` in the commit message. Do not add anything else.

## Owns (touch only these)
- `Packages/PaseoUI/Sources/PaseoUI/Shell/ShellContainer.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Shell/ShellDrawer.swift`
- `Packages/PaseoUI/Sources/PaseoUI/DesignSystem/Components/ShellHeader.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatHeader.swift`
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatScreen.swift`
- new test files only, if useful. Never edit an existing test.
Anything else you think must change goes in "Found, not fixed".

## Item A: the side panel opens too wide
`ShellContainer.swift:79` is `private var drawerWidth: CGFloat { (width * 0.82).rounded() }`. The Claude
app's panel is about 75 percent of the screen. Change `0.82` to `0.75`. Then `grep -rn "0\.82\|drawerWidth"`
in `Packages/PaseoUI` and make sure nothing else hard-codes the old fraction (anything derived from
`drawerWidth` follows by itself). Do not touch the parallax constant.

## Item B: the sidebar button opens the panel but does not close it
Today the hamburger button in the chat header calls an "open sidebar" action. When the panel is already
open the chat sits pushed to the right and the button is still visible as a sliver; tapping it must
**close** the panel.
1. Read `ShellDrawer.swift` fully: `state`, `open(_:)`, and what closes a surface (look for `close`,
   `dismiss`, `toggle`).
2. Find where the chat header's sidebar button gets its action: `grep -rn "Open sidebar\|\.sidebar(" Packages/PaseoUI/Sources`
   (start from `DesignSystem/Components/ShellHeader.swift:44` and `Conversation/Screen/ChatHeader.swift`;
   also `Draft/DraftChatView.swift:66`). Follow the action up to where it calls `drawer.open(.sidebar)`.
3. Make that action a toggle: if `drawer.state == .sidebar` close it, otherwise open it. Use an existing
   `ShellDrawer` method for closing; if none is public, add one small method to `ShellDrawer` that calls the
   same container close path the swipe and tap-outside use (find it in `ShellContainer.swift`; do not invent
   new motion code). Keep haptics and animation exactly as the existing open path does.
4. Check the pushed-aside chat surface does not swallow the tap: read how `ShellContainer.swift` handles a
   tap on the main surface while the sidebar is open (search for `tap`, `scrim`, `close`). The button must
   receive the tap. If something intercepts it, explain what in the final message and make the smallest fix
   inside the owned files.
The label stays "Open sidebar" when closed; when open use the label "Close sidebar" (accessibility label only).

## Item C: the top of the chat has a blur; it must be plain and readable
Now: `Conversation/Screen/ChatScreen.swift` has `.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])` and
`.safeAreaBar(edge: .top) { topChrome }`; `ChatHeader.swift` draws a `backdrop` gradient (`TranscriptHeader.backdropOpacity`,
`backdropFadeLocation`) behind the bar. Content shows through and fades under the clock and buttons.
Wanted: no blur and no see-through fade at the top. The area behind the status bar and the header is a
solid `Palette.background` fill, so scrolled content is cut off cleanly under it and everything stays readable.
1. Change the **top** scroll-edge effect to the hard style and keep the bottom as it is:
   `.scrollEdgeEffectStyle(.hard, for: .top)` and `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
   (Use exactly these enum cases; they exist in the SDK: `ScrollEdgeEffectStyle.hard` and `.soft`. If
   `.hard` does not compile in your reading of the SDK, stop and say so instead of guessing.)
2. In `ChatHeader.swift` replace the gradient `backdrop` with a solid fill of `Palette.background` that
   extends under the status bar (use `.ignoresSafeArea(edges: .top)` on the background only). Delete the
   gradient code and any constants that become unused. Keep the header hide-on-scroll behaviour as is.

## Item D: the title is a pill, not a bar
Now the title sits in the middle of the header bar. Wanted: the title (and its subtitle) sits inside a
**pill** (a capsule with a solid fill and a hairline border from `Palette`/tokens), the two circular glass
buttons stay as they are on each side, and there is no full-width bar and no blur behind any of it.
1. In `ChatHeader.swift`, find the title view inside `ChatHeaderBar` (the `Agent menu, <title>` button).
2. Give its content `.padding(.horizontal, Space.md)` and a capsule background:
   `.background(Palette.surface, in: Capsule())` plus `.overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1))`.
   Use only token names that exist: grep `Palette.surface` and `Palette.cardBorder` in `DesignSystem/` first
   and use the closest existing tokens if a name does not exist. The pill must keep a 44 pt minimum height
   (`minHeight`, not `height`) and `lineLimit(1)` on the title.
3. The pill's width hugs its text up to the room between the two buttons, then truncates the title (tail).
This is a visual change; the lead will check it on the simulator, so keep it minimal and do not redesign.

## Proof
`swiftc -parse` every edited file (`. ~/.local/share/swiftly/env.sh` first). The lead builds on the Mac gate and
looks at it on the simulator. Run `Tools/style-lint/style-lint.sh` on your files: no new hits. Commit as
`N1: chat chrome without blur, title pill, 75% panel, sidebar button toggles`.

## Final message
What you changed per item (A to D), the exact lines of each, every Apple API or token you were not sure
of, anything that did not match this ticket (say so instead of improvising), and "Found, not fixed".
