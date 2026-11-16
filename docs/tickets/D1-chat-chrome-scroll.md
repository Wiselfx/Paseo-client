# D1: chat chrome and scroll

Branch `d1-chrome`, from `foundation`. Read `_D-common.md` first.

**Owns:**
- `Conversation/Screen/ChatScreen.swift`
- `Conversation/Screen/ChatHeader.swift`
- `Conversation/Screen/ChatController.swift` (scroll state, `send*` and line ~861 only)
- `Conversation/Screen/SubagentPill.swift`
- `Conversation/Transcript/ChatTranscript.swift`
- `Conversation/Transcript/ChatTurnRail.swift`
- `DesignSystem/Components/ShellHeader.swift`
- `Draft/DraftChatView.swift` (header and stage layout only, **not** the composer call)

You don't own `ChatComposer.swift` (D2). The composer view is placed by you and drawn by D2.

## 1. The header must not be a box

**Today:** `ChatScreen` is a `VStack` of header, transcript, composer. The transcript is clipped at
a hard horizontal line under the 48 pt header and another one above the composer. On device it
reads as "a bar sitting on a box".

**Target** (the Claude iOS app): the transcript runs full height under both bars. The header is
only its two floating glass buttons plus the centred title, with no band. Content scrolling under
it dissolves through Apple's soft scroll-edge effect. The same happens under the composer.

**Build:**
- The transcript `ScrollView` is the screen's base layer and ignores nothing but the keyboard.
- Attach the chrome with iOS 26 `safeAreaBar`:
  - `.safeAreaBar(edge: .top) { header (+ find bar when open) }`
  - `.safeAreaBar(edge: .bottom) { SubagentPill + ComposerView }`
- Add `.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])`.
- The bars have **no background of their own**: the system's edge effect is the background.
- Delete `transcriptFade` (the 40 pt gradient). The edge effect replaces it.
- **Empty and loading states:** when `TranscriptView` shows `LoadingState` / `EmptyState` / the error
  banner instead of the scroll view, put them in a `ScrollView` too (non-scrolling content,
  `.scrollDisabled(true)` when it fits), so the bars attach the same way and nothing jumps when the
  first turns arrive.
- **The title** keeps its serif `.title` and the workspace line, and gets a little breathing room:
  `.padding(.top, Space.xs)`. The title block must not draw a background.
- **The draft screen** (`DraftChatView`) gets the same treatment: header in a top `safeAreaBar`
  over its stage; the composer stays where it is (the draft has no scroll content).
- **Fallback (only if the Mac gate rejects `safeAreaBar` / `scrollEdgeEffectStyle`):**
  `safeAreaInset(edge:)` with a 24 pt `LinearGradient` mask from `Palette.background` to clear
  under each bar. Say so in your final message.

## 2. Sending brings your message into view (it doesn't today)

**Today:** `ChatController.send` sets `anchoringToAnswer = true; isFollowing = false` and nothing
scrolls. If you had scrolled up, your message lands off-screen.

**Target** (Claude's behaviour): the moment you send, your bubble glides to the **top** of the
viewport (under the header), and the answer streams in beneath it. The view stays put while the
answer grows, until the answer overflows the screen; from then on it follows the tail.

**Build:**
- **Runway.** When the new user turn appears in `store.turns` while `anchoringToAnswer` is true:
  - add a bottom spacer to the lazy stack (before the `"bottom"` marker) of height
    `max(0, viewportHeight − lastTurnHeight − topBarInset)`;
  - measure `lastTurnHeight` with `onGeometryChange` on the last turn only, writing one `@State`;
  - recompute the runway when that height changes. It shrinks as the answer grows and reaches 0 when
    the answer fills the screen.
  - **Never remove the runway abruptly while it's on screen.** It stays (shrunk) until the next
    send, or until the conversation is reopened, which starts with no runway.
- **Scroll.** Then `withAnimation(Motion.glide.resolved(reduceMotion:)) { proxy.scrollTo(newTurnId, anchor: .top) }`.
  The runway is what makes `.top` reachable.
- **Follow.** While anchored, `defaultScrollAnchor(for: .sizeChanges)` is `.top`. Once the answer
  overflows (the runway is 0 and the distance from the bottom is ≤ 8), switch to following.
- **Where the logic lives.** Keep it in `TranscriptView` / `ChatController`. `TurnRow` stays
  `Equatable` and closure-free.

## 3. The jump at the bottom

**Today:** scrolling is smooth until you reach the bottom, then it "becomes janky and jumps to
bottom". The cause:
- `followAnchor` flips between `.top` and `.bottom` as `isFollowing` toggles (on at ≤ 16 pt, off at
  > ⅓ viewport) **while the finger or the deceleration is still moving**.
- As the lazy stack re-measures rows near the end (estimated → real heights), the `.bottom`
  size-change anchor yanks the content.

**Build:**
- `isFollowing` may become **true** only when the scroll phase is `.idle`, and only if the distance
  from the bottom is ≤ 8. It becomes **false** as soon as the user drags up (phase `.interacting`
  and the offset moves away from the bottom by more than 8 pt).
- While the phase is `.interacting` / `.decelerating`, the size-change anchor is `.top` (never fight
  the finger). Track the phase in a plain reference holder (like `TranscriptScrollTrack`), not in
  `@State`, so it doesn't invalidate the body per frame. Only the derived `followAnchor` may change,
  and only at phase boundaries.
- **Streaming while following** stays pinned with **no animation** (as today).
- **The back-to-end button** appears when the distance from the bottom is > 1 viewport (not ⅓). It
  fades and scales from 0.9 with `Motion.fade`, and tapping it re-enables follow at once.
- **Check on device in your head:**
  - flick to the bottom of a long finished conversation: it must decelerate into the end with no
    snap;
  - drag up 20 pt while an answer streams: it must release follow without a stutter.

## 4. Small

- **Turn rail.** `ChatTurnRail` draws its ticks over the user bubble's trailing edge. Give the rail
  a 6 pt inset from the trailing edge, and a soft `Palette.background` capsule backing at 0.85
  opacity behind the ticks while revealed, so it reads as a layer over the content rather than marks
  on it.
- **Deprecation.** `ChatController.swift` ~861: replace `UIScreen.main` with the window scene's
  screen (pass the display scale in from the view's `\.displayScale` environment).

## Proof

- `swiftc -parse` on every touched file.
- Final message: how the runway and the follow state machine work (states and transitions, in 10
  lines or fewer); any Apple API you were unsure of.
