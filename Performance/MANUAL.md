# MANUAL: the questions final-check.sh cannot answer for you

One entry per `[MANUAL]` item of [MUST.md](MUST.md). `final-check.sh` block 3 prints the entries that apply to your diff
(from the paths and the features it finds in your changed lines) with the file:line of any heuristic hit. Answer yes/no; on
no or unsure do what the entry says; tick it in the sign-off with one clause. The script reads this file: keep the format.

### M01
**Ask:** Does every view you touched read only the store fields it draws (no field read just to forward it, no big body that reads a whole list)?
**If no or unsure:** Move the read into a small child view that draws it (SidebarDirectoryHost pattern); if you cannot, escalate.
**Re-read:** MUST.md section B (M01); PATTERNS/observation-and-invalidation.md

### M04
**Ask:** Can any store setter you added or changed run with a value equal to the one held (push, poll, reconnect, repeated snapshot)? If yes, does it compare first?
**If no or unsure:** Write `if a != b { a = b }`; sort a copy and assign only if the order changed; add a Swift Testing test (TEMPLATES/tests.swift.md).
**Re-read:** MUST.md section B (M04); PATTERNS/stores-and-core.md

### M05
**Ask:** Does any per-event path (key, scroll, tick) assign a tracked struct or class property whose value usually stays the same?
**If no or unsure:** Keep the machine @ObservationIgnored and publish the one drawn value only when it changes (ChatController.mascotState).
**Re-read:** MUST.md section B (M05); PATTERNS/stores-and-core.md

### M07
**Ask:** Does your change pass a closure, binding or changing value through the environment, or re-assign a hosting root, for something that flips during a drawer motion or a focus?
**If no or unsure:** Use an observable flag object read by the one child that needs it (SurfaceFlags) or an Equatable key (ShellRootsKey); never a closure in the environment.
**Re-read:** MUST.md section B (M07); PATTERNS/animation-and-drawer.md

### M09
**Ask:** Is every `.id(`/ForEach id a stable entity id, does each item keep one place in the tree across its states, and does each item get only what is true for it (e.g. `isStreaming && isTail`)?
**If no or unsure:** Change the id to the entity id (`seq:<seqStart>`, agentId). For anchors that must change use rowAnchor. If an id must follow a changing value, escalate.
**Re-read:** MUST.md section B (M09); PATTERNS/identity-and-streaming.md

### M11
**Ask:** Is every repeated view you added or changed Equatable on the inputs that decide what it draws (not colour tokens or closures) and applied with `.equatable()`? Any AnyView in repeated content?
**If no or unsure:** Add Equatable on a value model + `.equatable()` (TEMPLATES/row.swift.md). Replace AnyView with a @ViewBuilder switch.
**Re-read:** MUST.md section B (M11); PATTERNS/rows-and-lists.md

### M12
**Ask:** Can the list/stack you touched hold more than 30 items, and is it a Lazy container (or a window)? Are sheets/menus built only when presented?
**If no or unsure:** Use LazyVStack/List; mount a window for transcripts; move sheet/menu content behind its presentation. If the count can only be 12 or fewer, say so in the tick.
**Re-read:** MUST.md section B (M12); PATTERNS/lazy-stacks-and-scrolling.md

### M14
**Ask:** Does every row/card reserve its final size before it appears, and does anything change a row's height after it appears (image load, expand)?
**If no or unsure:** Reserve with a fixed or measured frame; read width with onGeometryChange written on change; if height must change, escalate.
**Re-read:** MUST.md section B (M14); PATTERNS/media-and-images.md

### M16
**Ask:** Is every sort/filter/group/Set/map over a store collection built once per pass (store or memo), not per row, per body, or per keystroke?
**If no or unsure:** Move it into the store (maintained incrementally) or a small memo class keyed on its inputs (FileListMemo, PieceMemo).
**Re-read:** MUST.md section B (M16); PATTERNS/rows-and-lists.md

### M18
**Ask:** Can any work you added take more than 4 ms on the main thread (parse, highlight, decode, scan, layout of long text, image work) or grow with content length?
**If no or unsure:** Do it off main (Task.detached + cache, ProseWarmup pattern) or in slices with reserved space; make the per-frame/per-token part O(1). If you cannot prove it is under 4 ms, escalate with a measurement.
**Re-read:** MUST.md section B (M18); PATTERNS/hot-paths-and-indexing.md (per-frame access); PATTERNS/text-markdown-code.md (parse/highlight)

### M20
**Ask:** Does a streamed delta change only the tail (no re-split or rebuild of settled pieces, no id change, no flag that flips for every piece)?
**If no or unsure:** Pass each piece its own truth; memoise the split; keep one slot for streaming and completed states. Run stream.sh if you touched this path.
**Re-read:** MUST.md section B (M20); PATTERNS/identity-and-streaming.md

### M21
**Ask:** Do you scroll programmatically in a lazy stack by more than about 5 screens, change the turn window, or end the open re-seat on a layout heuristic?
**If no or unsure:** Do not. Use a window around the target or bounded hops; the re-seat ends on focus, a finger, a send or a find. Do not change windowSize/windowStep: that is BLOCKED, not an escalation.
**Re-read:** MUST.md section B (M21); PATTERNS/lazy-stacks-and-scrolling.md

### M25
**Ask:** Does every Task/timer/stream you started have an owner that cancels it (disappear, deinit, id change), run at most once per view not per row, and avoid hopping to the main queue from main-actor code?
**If no or unsure:** Use `.task(id:)` or a stored Task cancelled in deinit/teardown (TEMPLATES/task.swift.md); drop the DispatchQueue.main hop.
**Re-read:** MUST.md section B (M25); PATTERNS/concurrency-and-main-thread.md; PATTERNS/hot-paths-and-indexing.md section 5 (a task started from a method)

### M26
**Ask:** Do disk writes, JSON encode/decode, file reads or Keychain access you added run off the main thread (or on a serial writer), and are writes coalesced?
**If no or unsure:** Take a value snapshot on main, encode and write on a serial utility queue (DraftFileWriter); coalesce with a timer.
**Re-read:** MUST.md section B (M26); PATTERNS/concurrency-and-main-thread.md

### M27
**Ask:** Does any hot callback (body, canPerformAction, scroll/layout callback, per-key path) call IPC (pasteboard, camera probe, Keychain, system settings)?
**If no or unsure:** Cache it (`static let` or a small state object) and refresh on the system notification (PasteboardImageState).
**Re-read:** MUST.md section B (M27); PATTERNS/uikit-interop-and-keyboard.md

### M29
**Ask:** Is every cache or memo you added bounded by count AND cost, locked if touched off main, keyed exactly as the reader keys it, and (for images) evicted on memory warning?
**If no or unsure:** Copy ProseCache (TEMPLATES/cache.swift.md); add a bounds test; if the key is a full streamed string, key on a hash plus length.
**Re-read:** MUST.md section B (M29); PATTERNS/caches-and-memory.md

### M30
**Ask:** Does your change keep stores, subscriptions or streams alive for every item ever opened, or use an unbounded buffer?
**If no or unsure:** Bound by recency plus busy (HostSession.retainedConversationLimit pattern); use a bounded buffering policy; add a test.
**Re-read:** MUST.md section B (M30); PATTERNS/stores-and-core.md

### M31
**Ask:** Do you create a costly object (WKWebView, audio engine, text view, highlighter, formatter) in an init, a body or the chat-open path?
**If no or unsure:** Build it lazily on first use or warm it once at idle at a chosen moment (ComposerWarmup, prewarm after the open re-seat). Never in init.
**Re-read:** MUST.md section B (M31); PATTERNS/launch-and-startup.md

### M33
**Ask:** Does anything you added run before the first frame (App init, launch, scene setup) that is not on the list: read defaults, register fonts in one call, build the shell?
**If no or unsure:** Move it after the first frame (start(), `.task`) or to idle; batch system registrations.
**Re-read:** MUST.md section B (M33); PATTERNS/launch-and-startup.md

### M34
**Ask:** Is every updateUIView/updateUIViewController you wrote idempotent (compares before assigning, no work when inputs are equal) and the representable Equatable?
**If no or unsure:** Guard each assignment with `if view.x != new`; add Equatable on the inputs (ClaudeSelectableInlineCode pattern); memoise expensive sizing (fit memo).
**Re-read:** MUST.md section B (M34); PATTERNS/uikit-interop-and-keyboard.md

### M35
**Ask:** Does anything track a finger across the screen in SwiftUI (DragGesture writing state per event) or animate a drawer/panel with SwiftUI state per frame?
**If no or unsure:** Move it to a UIKit container with UIPanGestureRecognizer and a velocity-matched spring (R-3); that pattern is yours to write. Changing the shell container itself is the lead's: `ESCALATE:` it.
**Re-read:** MUST.md section B (M35); PATTERNS/animation-and-drawer.md

### M37
**Ask:** Does every endless animation, TimelineView, timer or poll you added stop when the surface is obscured, the mascot sleeps, or reduce motion is on?
**If no or unsure:** Gate it on isSurfaceObscured / scenePhase / state and cancel it (SidebarUsageDriver, MascotDriver.ticking).
**Re-read:** MUST.md section B (M37); PATTERNS/animation-and-drawer.md

### M40
**Ask:** Does this change carry its evidence: for a hot path, before -> after numbers from MEASURE.md (3 cold runs, median + range); for a store, a test; and no baseline, budget or bound grew?
**If no or unsure:** Run MEASURE.md for hot-path files, or write the reason it cannot affect one. Add the test (TEMPLATES/tests.swift.md). A baseline must not grow: raising one is BLOCKED, not an escalation.
**Re-read:** MUST.md section B (M40); MEASURE.md
