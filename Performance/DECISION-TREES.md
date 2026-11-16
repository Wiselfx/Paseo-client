# Decision trees: "I am adding X"

Find X, follow the numbered steps in order. Every step is a yes/no or a lookup. Where the call is not yours it says ESCALATE
(write the parts a pattern covers, flag the decision, keep going: [FINAL-CHECK.md](FINAL-CHECK.md)) or BLOCKED (do not write it).
Ids: M.. = [MUST.md](MUST.md), PF-.. = [RULES.md](RULES.md), templates in [TEMPLATES](TEMPLATES/). Finish every tree with [FINAL-CHECK.md](FINAL-CHECK.md).

## A new row or list view
1. Can the collection exceed 30 items? Yes: `LazyVStack`/`List` (M12). No: any stack, and say "<= 12 fixed items" in the sign-off.
2. Copy [row.swift.md](TEMPLATES/row.swift.md): a value model (Equatable) + one actions object, `==` on the model only, `.equatable()` at the call site (M10, M11).
3. ForEach id: an entity id. Never `\.offset`, never a streaming value (M09).
4. Anything computed from a store collection (sort/filter/group/Set/lookup)? Build once per pass in the store or a memo (`FileListMemo`), pass the result in (M16).
5. Row size known before it appears? Reserve it. Cannot? Do not invent one: record `ESCALATE: row height not reserved` (M14). Needs a width: `onGeometryChange`, written on change.

## A new observable store or property
1. Does a setter receive repeated values (push, poll, reconnect, snapshot)? Yes: compare first (`if a != b { a = b }`), sort a copy (M04).
2. Is it written per event (key, scroll, tick)? Publish only the one drawn value, keep the machine `@ObservationIgnored` (M05).
3. Does it persist or encode? Snapshot on main, write on a serial queue (M26, `DraftFileWriter`).
4. Does it keep objects per item opened? Bound it (recency + busy) (M30).
5. Add a Swift Testing test in a NEW file ([tests.swift.md](TEMPLATES/tests.swift.md)): equal write does not change, bound holds.

## A new view that reads a store
1. List the fields the view draws. Read exactly those (M01). A field only forwarded to a child is read by the child.
2. Need a binding to a store field? The view that edits it builds it from the store in its own body; never pass `Binding(get: store.x)` from a parent (M02).
3. Reads a flag that flips during motion (`isSurfaceObscured`, scene phase)? Put that read in a small child (`SidebarUsageDriver`) (PF-13).
4. Add `let _ = PaseoPerf.body("Name")` to see its body count while measuring ([instrumentation.md](TEMPLATES/instrumentation.md)); keep it, remove `diff`.

## A new sheet, popover or menu
1. Content is built when presented, not inside every row (M12). A row's context menu is lazy or shared.
2. Presented state lives in the owner of the trigger, not in the row. A row opens it through the actions object.
3. Uses a list? Go to "A new row or list view". Uses a store? Pass the store to the sheet root, not a snapshot copy of a big struct.

## A new image or media view
1. Decode through the existing pipeline at the drawn size, off main (M18); never `UIImage(data:)` or `AsyncImage` in a view.
2. Reserve the size; read width with `onGeometryChange` (M13, M14). New cache? see "A new cache".
3. Web content? Use the shared `RichWebSnapshotRenderer`, never a new `WKWebView` (M31). Network fetch only on cheap links.
4. Measure: rich-media scroll scenario ([MEASURE.md](MEASURE.md)).

## A new UIViewRepresentable
1. Copy [representable.swift.md](TEMPLATES/representable.swift.md): `Equatable` on the inputs, `updateUIView` compares before assigning (M34).
2. Sizing calls (`sizeThatFits`) memoised on a key listing every input; else do not memoise.
3. Gesture tracking a finger? BLOCKED: do not add it here; finger-tracked motion belongs in the shell container (M35).
4. Delegate/IPC calls (pasteboard, keyboard) cached with a notification refresh (M27).

## A new timer, Task or stream
1. Needs to survive the view? No: `.task(id:)` (cancelled on disappear). Yes: store the Task, cancel it in `deinit`/teardown ([task.swift.md](TEMPLATES/task.swift.md)) (M25).
2. Loop? `while !Task.isCancelled`, sleep inside, check again after the sleep (M24). Never `while true`.
3. Visible-only work? Key the task on the visibility fact (`isSurfaceObscured`, `scenePhase`) and return early (M37).
4. One per row? No: move it to the owner. Several in flight? Bound them (a count or a serial queue).
5. Stream buffer: `.bufferingNewest(n)`, not `.unbounded` (M30).

## A new cache
1. Copy [cache.swift.md](TEMPLATES/cache.swift.md): count limit AND cost limit, `NSLock` if anything off main touches it (M29).
2. Key = exactly what the reader keys on (a warm-up with a different key warms nothing).
3. Images: `NSCache` with both limits, evict on memory warning. Dates/strings: bounded dictionary like `PaseoDate`.
4. Add the bound test ([tests.swift.md](TEMPLATES/tests.swift.md)). Unbounded for any reason: BLOCKED, not written.

## A lookup over a store collection (an index, a position, a row)
1. Where is it read? Once per user action: O(n) is fine, and say so in the M18 tick. From a body pass, a scroll or
   geometry callback, or a tick: it must be O(1) or O(log n) (M18, [hot paths](PATTERNS/hot-paths-and-indexing.md)).
2. Ordered array? Binary-search it (`FindNavigation.firstTurnIndex`) and state the invariant that makes the search valid.
   Not ordered? Keep the index in the store, updated once per store change.
3. Need the nearest built or visible item? Search outward from the target (`FindNavigation.nearestIndex`); a tie goes to the
   lower index. Do not build an array of every candidate (M41, C48, H29).
4. In a scroll handler, read the O(1) condition first so most frames never reach the O(n) lookup.
5. Pin the fast path with a test that compares it with the plain scan on duplicates and ties (new file, [tests](TEMPLATES/tests.swift.md)).

## A Task, fetch or timer started from a method
1. Does a view own it and key it? `.task(id:)` (M23). Loop? `while !Task.isCancelled`, sleep inside, check again (M24).
2. Does a method start it (a find step, a save, a load)? Keep the handle; cancel it on close, deinit and on the next call
   (`TranscriptJumpRunner.runAfterFetch`); a discarded `Task {` in a method is H30 (M25).
3. After every await inside the work, `guard !Task.isCancelled else { return }`: cancelling a task does not stop a closure
   that is already waiting.
4. Visible-only work: gate on the visibility fact (`isSurfaceObscured`, `scenePhase`) and return early (M37).
5. Several in flight? Bound them or make them supersede each other; never one per row.


## A new store write path or persistence
1. Compare-before-write (M04). 2. Encode/write/decode off main, value snapshot taken on main (M26). 3. Coalesce frequent writes; first change goes out at once; `flush()` on background.
4. Test it in a new file. 5. Touches `HostSession`/`ConversationStore`/`TimelineState`? Hot path: measure (typing and streaming scenarios).

## Launch-time work
1. Is it on the first-frame list (defaults, one font call, the shell)? Yes: keep it cheap. No: after the first frame (`start()`, `.task`) or at idle (M33).
2. Costly object (web view, audio engine, text view)? Lazy, or warm once at idle at a moment no interaction lands on (M31). Never in `init`.
3. System registrations batched (fonts: one call) (M32). 4. Measure the open and idle scenarios; a cost that moved to a later moment is not a fix.

## A new animation
1. Token from `Motion`, `.resolved(reduceMotion:)` (M36). No literal animations.
2. Follows a finger? BLOCKED: it belongs in a UIKit pan (R-3, M35). 3. Endless (`repeatForever`, `TimelineView(.animation)`, timer)? It stops when obscured, asleep or reduce motion (M37).
4. Inside a row or the transcript? `withAnimation` there is a manual question: it must not change layout of settled rows. Avoid `mask`/`blur`/`shadow`/`drawingGroup` in repeated content (offscreen pass).

## A new environment value
1. A plain value (Bool, enum, small struct) is fine. A closure or binding in the environment is not (PF-19, M07): put the methods on a stable object and pass the object.
2. Who reads it? Only views that draw it. A big body must not read it just to forward it.
3. Changes during a motion or focus? Use an observable flag object (`SurfaceFlags`), not a new environment value per change.

## A text or markdown rendering change
1. Does the view stay Equatable on layout inputs (not colour tokens)? (M11) 2. Any scan: O(n), no `count` on a suffix (M17).
3. Parse/split/highlight over 4 ms? Off main with a thread-safe bounded cache under the view's key (M18, M29).
4. Look unchanged at xs, m, ax5, light and dark? Else BLOCKED: a visible change was not asked for (R-6). 5. Measure streaming and open scenarios.

## A streaming change
1. A delta changes the tail only (M20). 2. Identity: no `.id` on moving values; anchors are overlays (M08). 3. Each piece gets its own truth (`isStreaming && isTail`) (M09).
4. Run `StreamingIdentityTests`; add the case you changed. 5. Measure `stream.sh` (3 runs): `Markdown` bodies per update <= 1.

## Anything in the transcript, composer or shell
1. Is your change one of the patterns in [PATTERNS](PATTERNS/) applied as written? Yes: proceed, cite the pattern in the commit.
2. No: do not improvise. Apply the parts a listed pattern covers, write the rest down as
   `ESCALATE: <what>` (or `BLOCKED:` for step 3's items), and stop that part. These paths carry the rejected
   options (D01 to D07) and the floors; improvising here cost passes 2 to 11.
3. BLOCKED: never change `windowSize`/`windowStep`, the re-seat's end condition, the roots assignment, keyboard
   behaviour or the hosting container. These are not yours to write, even with an ESCALATE line.
4. Always measure (3 cold runs) and paste the evidence block.
