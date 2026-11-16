# N6: one composer (stop rebuilding it), header hides only the title pill, text-size overlap

Read `AGENTS.md`, then `docs/tickets/_L-common.md`, then `docs/tickets/N3-chrome-followup.md` (what the header looks like now).

## A. The composer is rebuilt at every empty/non-empty swap of the chat (measured fix)
**Evidence (simulator, 2026-11-15, a live-instance counter on the composer's UIKit text view):** with the current
code the composer is created twice at launch and again at every rewind (an orphan that is never attached) and at the
next send (a second attached copy), so `live` grows 2, 3. Cause: `Conversation/Transcript/ChatTranscript.swift`
`content` swaps between two different `ScrollView`s: `states` (loading / empty / failed) and `transcript`. The bottom
bar is attached to whichever is current, and the swap rebuilds it. **Fix tested on the simulator** (composer created
once, `live=1` through launch, rewind, send and reply): keep both mounted and draw the state view on top:
```swift
@ViewBuilder private var content: some View {
    ZStack {
        transcript
        if store.turns.isEmpty, store.pendingPermissions.isEmpty {
            states
        }
    }
}
```
Apply exactly that (replace the `if/else`). Then read `states` and `transcript` for anything that assumed only one is
alive at a time and report it: `onAppear`/`onDisappear`/`.task` side effects on the transcript while it is empty
(`shellDrawer?.trailingEdgeReserved`, `store.subagents.load()`, runway/anchoring state, `scrollPosition`), the
`.simultaneousGesture` tap, the back-to-end overlay, and accessibility (the hidden empty transcript must not be read
by VoiceOver while the empty state is shown: add `.accessibilityHidden(true)` to `transcript` only while the state is
shown). Keep the focus guard in `ComposerTextView.bridgeFocus` as it is (do not touch it).

## B. The header hides only the title pill, never the two side buttons
Now `ChatTopChrome` (`Conversation/Screen/ChatHeader.swift`) applies `.offset`/`.opacity(hidden ? 0 : 1)`/
`.allowsHitTesting(!hidden)`/`.accessibilityHidden(hidden)` to the whole `ChatHeaderBar` when it hides on scroll.
Wanted (user directive): when it hides, **only the title pill** hides (same offset/fade as today); the left
(sidebar) and right (panel) circular buttons stay fully visible and tappable at every scroll position. The solid
backdrop from N3 stays behind everything. Implementation: `ChatHeaderBar.makeHeaderBar` builds
`ShellHeader(leading:title:trailing:)` (`DesignSystem/Components/ShellHeader.swift`). Pass the hidden state into
`ChatHeaderBar` (a `Bool` parameter) and apply the hide modifiers only to the `title:` content (`titleMenu`), and
remove them from the outer header. The header's layout height must not change when the pill hides.

## C. Title and subtitle overlap at the biggest text size
**User-confirmed bug:** at the largest Dynamic Type sizes (accessibility sizes) the title and its subtitle draw on top
of each other and the text runs under the bar. In `ChatHeader.swift` the pill content is `headerTitle`
(`Text(store.agent?.title ?? "Agent")`, `.font(.paseo(.headline))`, `lineLimit(1)`) over `headerWorkspace(...)`.
Find any fixed height/frame/offset in that VStack or in `ShellHeader` (`.frame(minHeight: 48)` is fine; a fixed
`height`, `.offset` or negative padding is not) and make the title block grow with the text: no fixed heights, the
two lines stacked with a small spacing token, the pill sized by its content, `minHeight` only. Under accessibility
sizes allow the pill to take more height while the buttons stay 44 pt and aligned to the top row. You cannot run it:
reason about the layout carefully and list your assumptions; the lead checks it at the biggest size on the simulator.

## Owns (touch only these)
`Conversation/Transcript/ChatTranscript.swift`, `Conversation/Screen/ChatHeader.swift`,
`DesignSystem/Components/ShellHeader.swift` (all under `Packages/PaseoUI/Sources/PaseoUI/`); new test files only.

## Proof
`swiftc -parse` each edited file, grep every symbol, `Tools/style-lint/style-lint.sh` on the files. Commit as
`N6: one composer, header hides only the title pill, title block grows with text`.

## Final message
Per item A to C: what changed (file:line); for A the list of side effects you checked and what you found; every
API or token you were unsure of; "Found, not fixed".
