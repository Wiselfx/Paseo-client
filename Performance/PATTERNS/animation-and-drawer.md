# Animation and drawer

Rules: PF-7, PF-36; AGENTS R-3, R-4. MUST: M07, M35, M36, M37. Checks: C21, H10, H13, H25, H26, F09, F14.

## 1. Finger-tracked motion runs in UIKit (R-3)
The drawers and the panel are `ShellContainer`: UIKit views moved by `UIPanGestureRecognizer`, handed off to a velocity-matched `UISpringTimingParameters(dampingRatio: 1)`.
SwiftUI hosts the content and learns only open/closed. A SwiftUI `DragGesture` that writes `@State` per event re-evaluates bodies per frame (H26): do not add one.
Audit leftovers (never confirmed on a phone): up to five simultaneous `DragGesture`s over the transcript; full-screen dim and hairline layers re-created per frame.

## 2. First and last frame of a motion: flags, not roots (`9b271ee`, `b27adb8`; settle stall 52 to 156 -> 10 to 36 ms; Release 16 ms max)
See [observation](observation-and-invalidation.md) section 3 and 5. `SurfaceFlags` per surface, read through `\.isSurfaceObscured` / `\.isPanelVisible`, written only on change.
The sidebar's remaining bodies at the settle were traced to the usage driver and moved into `SidebarUsageDriver`.

## 3. Endless animation stops when nobody sees it (PF-36)
```swift
private var ticking: Bool { controller.mascotState != .sleeping && !isSurfaceObscured }
.task(id: ticking) { guard ticking else { return }
    while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }; controller.tickMascot() } }
```
Candidates still open from the audit: `TimelineView(.animation)` at display rate while the crab sleeps; masked text sweeps (`mask` forces an offscreen pass); `.repeatForever` dots; a 4 Hz `Timer.publish`.

## 4. Tokens only (R-4)
BAD: `withAnimation { open.toggle() }`, `.animation(.spring(), value:)`. GOOD: `withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) { userExpanded = true }`.
Haptics via `Haptics`, never `UIImpactFeedbackGenerator` in a view. Anything animated honours reduce motion.

## 5. Rejected
`shouldRasterize` on the sliding drawer (D05): visual risk, not shipped. Mounting the sidebar later (D02): moved the cost to the first tap.

If you remember nothing else:
- Anything that follows a finger is UIKit; SwiftUI is told "open" or "closed" once.
- Chrome flips by writing a flag when it changed; never re-assign roots at the start/end of a motion.
- Endless animations and timers carry a visibility gate and use `Motion` tokens with reduce motion.
