# R5: the shell, rebuilt on a UIKit drawer container

Branch: `r5-shell`, from `foundation` after R4 is merged. Read `docs/tickets/_R-common.md`, then
`docs/UX-SPEC.md` §1 (as amended: §1.2 now opens **anywhere**) and `docs/refactor/PLAN.md` §RB.

**Owns:**
- `Shell/` (`PaseoShellView.swift`, `EdgeDrawer.swift`, plus new files);
- `App/Sources/RootView.swift`;
- in `Workspace/WorkspacePanel.swift`, **only** the drawer plumbing: the `dismissDrag` parameter,
  `withPanelDismiss`, `PanelVisibilityTracker` and `PanelDismissDrag`.

Runs in parallel with R6 (Conversation), R7 (Workspace) and R8 (Settings). Don't edit their files
beyond the list above. If you need a hook from them, write it in your final message.

**This is the most important ticket of the round.** The user's #1 complaint is that the drawers lag.
The goal is drawers that feel like a system app's: the surface is glued to the finger, the release
keeps the finger's speed, and nothing ever bounces.

## 1. Architecture

```
ShellView (SwiftUI, public, replaces PaseoShellView; keep `public typealias PaseoShellView = ShellView`)
 └─ ShellContainer: UIViewControllerRepresentable
     └─ ShellContainerController: UIViewController
          ├─ sidebarHost:      UIHostingController<AnyView>   (bottom, never moves)
          ├─ conversationCard: UIView (rounded, masks) ── conversationHost: UIHostingController<AnyView>
          │                                           └─ dimView (UIView, black, alpha) + hairline (layer border)
          └─ panelCard:        UIView (rounded, masks) ── panelHost: UIHostingController<AnyView>
                                                       └─ hairline
```

- `ShellView` builds the three SwiftUI roots (the sidebar, the main conversation/draft and the
  panel) and passes them to `ShellContainer`. `updateUIViewController` reassigns
  `host.rootView` for each surface. That is cheap, because `ShellView.body` must re-evaluate rarely
  (§4).
- **Bridge object** (`@MainActor final class ShellDrawer`, provided to SwiftUI as
  `@Environment(\.shellDrawer)`):

  ```swift
  enum Surface { case none, sidebar, panel }
  func open(_ surface: Surface)            // animated with Motion.settle
  func close()
  private(set) var state: Surface          // committed state only
  var trailingEdgeReserved = false         // the turn rail is visible: no panel edge pan
  var panelHandlesBack = false             // the panel's inner NavigationStack is deeper than root
  var onStateChange: ((Surface) -> Void)?  // ShellView mirrors it into @State for a11y/pausing
  ```

  Views never read `progress`. Nothing in SwiftUI is invalidated per frame.
- `\.isSurfaceObscured: Bool` (defined in R4's `StatusDot` file; reuse it). It is true for the conversation root while
  the sidebar or panel is open **or moving**, and true for the panel root while it isn't open. The
  container flips it with `rootView` updates **only at the start and end of a motion**, never per frame.

## 2. Geometry and material

Let `width` be the container width.

| Value | Formula |
|---|---|
| `drawerWidth` | `round(width * 0.82)` |
| `parallax` | `0.3 * width` |
| `sidebarProgress s ∈ [0,1]`, `panelProgress p ∈ [0,1]` | at most one is non-zero |
| `conversationCard.transform` | `translationX: drawerWidth * s - parallax * p` |
| `panelCard.transform` | `translationX: width * (1 - p)` |
| `dimView.alpha` | `max(s, p) * (dark ? 0.55 : 0.25)`, on the conversation card above its content |

- **Dark:** `traitCollection.userInterfaceStyle == .dark`. Update it on trait change.
- **Cards:**
  - `layer.cornerRadius = 55`, `layer.cornerCurve = .continuous`, `masksToBounds = true`. This is
    constant; never animate the radius.
  - Hairline: `layer.borderWidth = 0.5`, with `borderColor` = ink at 10 % (resolve the dynamic
    color on trait change). Its opacity follows progress. Animate the border through a separate
    full-size `CAShapeLayer` (`path` = a rounded rect with a continuous curve, `strokeColor`,
    `lineWidth` 0.5) whose `opacity = s` (the conversation) or `p` (the panel). Don't use
    `layer.border`, which can't fade.
- **Full bleed:** every host view fills the container (`frame = bounds`, autoresizing), including
  the safe areas. The SwiftUI roots handle safe-area padding themselves, as today.
- **Panel:** `isHidden = true` and `accessibilityElementsHidden = true` when `p == 0`.
  - The panel root is **not torn down** when closed. It keeps the tab and scroll per workspace
    (UX-SPEC §1.3).
  - Its pages stay unmounted while closed: pass `isPanelVisible` into `WorkspacePanel` through an
    environment value. That replaces `PanelVisibilityTracker`, and keeps P5-D's mount-on-visible
    and release-on-close behavior.
- **Covered surface:** set `accessibilityElementsHidden = true` on the conversation card while the
  sidebar or panel is open, and on the sidebar host while it's closed.
- **The dim view** is a real control. Its tap closes, `isAccessibilityElement = true`, label "Close",
  traits `.button`. It is user-interactive only when `max(s, p) > 0`.

## 3. Gestures (`UIGestureRecognizerDelegate` on the controller)

One `UIPanGestureRecognizer` named `drawerPan`, installed on the controller's root view. The intent
is decided in `gestureRecognizerShouldBegin` from `velocity(in:)` and the start location (from
`location(in:)` at begin):

| State | Begins when | Drives |
|---|---|---|
| none | `vx > 0` and `abs(vx) > abs(vy) * 1.2`, **anywhere** on the conversation | sidebar open |
| none | `vx < 0`, `abs(vx) > abs(vy) * 1.2`, start `x > width - 24` and `!trailingEdgeReserved` | panel open |
| sidebar | `vx < 0`, horizontal-dominant, anywhere | sidebar close |
| panel | `vx > 0`, horizontal-dominant, anywhere in the panel, and `!panelHandlesBack` | panel close |

**Never begin** when any of these holds:
- the touch's hit view (`view.hitTest(start, with: nil)`), or any of its ancestors up to the card, is
  a `UIScrollView` that can scroll horizontally (`isScrollEnabled && contentSize.width > bounds.width + 1`);
- the hit view, or one of its ancestors, conforms to `UITextInput` and is the first responder (text
  being edited);
- `p == 0`, the gesture is a sidebar open, and the start `x > width - 24` while
  `trailingEdgeReserved` (that strip belongs to the rail).

**Winning against vertical scrolling without delaying it:** implement
`gestureRecognizer(_:shouldBeRequiredToFailBy:)`. Return `true` when the other recognizer is the
`panGestureRecognizer` of a `UIScrollView` inside the same card that **cannot** scroll horizontally.
The scroll views then wait for `drawerPan` to fail, and `drawerPan` fails at its first movement
when the movement isn't horizontal-dominant. So vertical scrolling starts with no added delay.
Return `false` from `shouldRecognizeSimultaneouslyWith`.

**Tracking (`.changed`):**
- `progress = clamp(origin + signedTranslation / distance, 0, 1)`, with `distance` = `drawerWidth`
  (sidebar) or `width` (panel);
- write the transforms, alpha and hairline opacity **directly** inside
  `UIView.performWithoutAnimation` / `CATransaction.setDisableActions(true)`;
- call `Haptics.prepare()` on `.began`;
- on `.began`, if the keyboard is up and the gesture opens the sidebar, `view.endEditing(true)`.

**Release (`.ended` / `.cancelled`):**
1. Projected end, using UIKit's deceleration projection (WWDC18 "Designing Fluid Interfaces"):
   `projectedPoints = (v / 1000) * 0.998 / (1 - 0.998)` (≈ `v * 0.5`, with `v` the signed velocity in
   pt/s along the opening direction), then `projected = progress + projectedPoints / distance`.
2. `open = projected >= 0.5`.
3. Animate to the target with `UIViewPropertyAnimator(duration: 0.32, timingParameters:
   UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: CGVector(dx: relV, dy: 0)))`, where
   `relV = v / (targetX - currentX)` in points (0 if the distance is < 1 pt). The finger's speed
   carries into the settle, and damping 1.0 means no overshoot.
4. Under Reduce Motion: `UIViewPropertyAnimator(duration: 0.2, curve: .easeOut)` and no velocity.

**Interruptible:** if a pan begins while an animator is running, stop it with
`stopAnimation(true)`. Read the current `translationX` from `layer.presentation()`, set the model
transform to it, derive `origin` from it, and keep tracking. The surface stops dead under the finger.

**Commit:** when an animation completes in a new state:
- update `state`, call `onStateChange` and set the accessibility hiding;
- `Haptics.selection()` exactly **once** per committed change (opening or closing; not on a
  cancelled settle back to the same state);
- on opening the sidebar, also `view.endEditing(true)`.

**Programmatic:** `open(_:)` / `close()` run the same animator with no velocity. Opening one
surface while the other is open animates both in the same animator (UX-SPEC §1.4: one curve, no
double animation).

**Escape:** override `accessibilityPerformEscape()` on the controller, returning true and closing
when a surface is open. Also add a `UIKeyCommand` for Escape (`UIKeyCommand.inputEscape`) that
closes.

## 4. ShellView: narrow observation, routing fixes

Port everything `PaseoShellView` does today:
- selection;
- drafts;
- notification and deep-link routing;
- presence;
- mention-in-chat.

On top of that:

1. **Body reads nothing that streams.**
   - `ShellView.body` must not read `session.agents`, `session.workspaceDirectory.*`,
     `session.connection` or `session.agentsError`.
   - Move the agent-list reaction (today's `.onChange(of: session.agents)`) and the
     directory-loaded reaction into a tiny modifier view `ShellSessionWatcher` with its own body,
     which calls back into the shell's routing.
   - It reacts to `session.agents.map(\.id)` changes only (an `[String]` value), not to every
     snapshot field.
2. **The panel and Mention follow the screen's workspace** (audit C #1).
   - `currentWorkspaceId = conversation?.agent?.workspaceId ?? draft?.workspaceId`.
   - The panel's workspace and Mention in chat both use it.
   - Mention into a draft appends to `draft.text` with the same spacing rule as the
     conversation path.
3. **One connection banner** (audit C #2).
   - A `ConnectionBanner` view in `Shell/` observes `session.connection` in its own body, and sits
     at the top of the conversation root above whatever is shown (chat or draft), below the
     status bar.
   - It uses `InlineBanner` (R4), with the existing wording:
     - `.reconnecting`: "Reconnecting…" with `InlineProgress`;
     - `.failed`: "Can't reach the host. Check that the daemon is running." with the action
       "Disconnect".
   - It enters and leaves with `Motion.fade`.
   - R6 deletes the chat's own banner.
4. **The empty main** (no agent, no draft) uses `ShellHeader(leading: .sidebar)`. The error text
   becomes `InlineBanner(.failure, …, action: ("Try again", { Task { await session.refreshAgents() } }))`.
5. **Toasts:** add `.toastHost(toastCenter)` once at the shell root, with the center created here and
   put into the environment (R4's `ToastCenter`).
6. **`RootView`:** move `.onChange(of: session.attention.pending)` and `deliverNotifications` into a
   small modifier view (`AttentionDelivery`), so `RootView.body` doesn't observe attention.
   Everything else in `RootView` stays.
7. **Keyboard commands** on the container:

   | Key | Action |
   |---|---|
   | ⌘K | Search (call the sidebar's search route through `ShellDrawer`: add `var onSearch`) |
   | ⌘N | New session |
   | ⌘\ | toggle the sidebar |
   | ⌘⇧\ | toggle the panel |

   Use `UIKeyCommand`s with `discoverabilityTitle` "Search", "New session", "Show sidebar" and
   "Show workspace". Those are approved labels.

## 5. Panel plumbing (`WorkspacePanel.swift`, plumbing only)

- Remove the `dismissDrag` parameter, `withPanelDismiss`, `PanelVisibilityTracker` and
  `PanelDismissDrag`.
- `isPanelVisible` comes from `@Environment(\.isPanelVisible)`, set by the shell.
- The back button calls `shellDrawer.close()`.
- **Files stack:** R7 turns Files into a `NavigationStack` and sets `shellDrawer.panelHandlesBack`
  from its path depth. Expose nothing else.
- Keep every other line of `WorkspacePanel.swift` for R7.

## 6. Delete

`EdgeDrawerDrag`, `edgeDrawerDrag(...)`, `ConversationCard`, `PanelCard`, `ShellOpenState`,
`EdgeDrawerDim`, `EdgeDrawerHairline`, `EdgeDrawerCard` (the card background is now the card view's
`backgroundColor` = `UIColor(Palette.background)`, dynamic), and `PanelDismissDrag`. Keep
`EdgeDrawer.settleAnimation` only if something outside the shell still uses it; otherwise delete
it too.

## 7. Acceptance (the lead checks the code; the user checks on the device)

1. **Tracking:** during a drag, no SwiftUI body is evaluated. The lead checks that nothing in
   `.changed` touches a SwiftUI state or `rootView`.
2. **Flick:** slow drag, then a flick. The card follows the finger exactly; the flick's speed
   continues into the settle; no overshoot.
3. **Interrupt:** catching a settling card stops it under the finger.
4. **Vertical scroll** in the transcript starts immediately and never moves a drawer.
5. **Horizontal content:** a horizontal swipe on a code block scrolls the code. A right swipe on
   chat text opens the sidebar.
6. **Panel close:** a right swipe anywhere on Agents closes the panel. On a diff it scrolls the
   diff. In a deep Files folder it goes back a folder (R7's stack).
7. **Accessibility:** VoiceOver doesn't read the covered surface. The two-finger scrub closes.
   The dim reads "Close, button".
8. **Haptics:** exactly one per open/close.
9. **Keyboard:** typing in the composer and then swiping right closes the keyboard and opens the
   sidebar.
10. **Rotation:** the app is portrait-only, but handle `viewWillTransition` anyway by re-laying out
    at the current state.

Final message: per `_R-common.md`. List every UIKit API you're unsure of, especially
`shouldBeRequiredToFailBy` semantics, spring `initialVelocity` units, and `layer.presentation()`.
