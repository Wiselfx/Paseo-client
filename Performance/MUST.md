# MUST: the sheet to keep open while you write Swift

Keep this open while coding; re-read section A before you report done. `[AUTO Cnn]` = `final-check.sh` guards it (a hit fails
the run). `[MANUAL]` = nothing guards it: you answer it in the sign-off ([MANUAL.md](MANUAL.md)). Ids PF-n: [RULES.md](RULES.md).

## A. Hard limits (numbers; terms in [GLOSSARY.md](GLOSSARY.md))
Frame budget 16.7 ms at 60 Hz, 8.3 ms at 120 Hz: the main thread must finish its UI update before that frame's commit
deadline. Apple's Hitches metric bands: <= 10 ms/s of hitch time is good, <= 25 is a warning, <= 50 critical, above 50 needs
immediate attention ([Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)).
- Hitch = a frame later than 1.5 budgets (`hit=`). Stall = main thread busy > 8 ms in one wake (`stall8=`, `smax=`). Jank = any hitch or stall a user can feel; zero on scroll, stream, typing, drawer, tap.
- Main thread: a `body` evaluates in < 1 ms (Apple marks a body over 500 us orange and over 1000 us red in Instruments: [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)); any single main-thread task <= 8 ms; anything that may exceed 4 ms is proven off-main or split into slices.
- Anything reachable from a body pass, a scroll/geometry callback or a tick is O(1) or O(log n) in content size; a scan or an index array there is O(n) per frame.
- Never on main: disk, network, IPC (pasteboard, camera probe, Keychain), large UserDefaults reads, JSON decode of big payloads, image decode, regex/formatter construction.
- First frame (launch) may do only: read defaults, register fonts in ONE call, build the shell. Keychain, connect, warm-ups, web view: after the first frame or at idle (2 s).
- Per interaction (Release; Debug is 1.3 to 3x worse): typing <= 20 ms stall per key and 0 `ChatScreen` bodies per key; tap answers next frame; scroll 0 hitches, no stall > 8 ms; stream <= 1 `Markdown` body per changed piece and 0 views created for settled pieces; drawer settle stall <= 36 ms and 0 sidebar/composer bodies per motion; open of a long chat median ~0.67 s (floor = cold render), no outlier > 1 s, no blank; media first scroll <= 30 ms; idle prints no window and `busy` < 5 %.
- Memory: every cache has a count limit AND a cost limit; locked if touched off main; images evict on memory warning; open conversations <= 6 plus busy ones.
- A view reads only what it draws; identity never follows a streaming value; rows are Equatable values + one actions object; no Task per row; every Task is cancelled on disappear; concurrency is bounded.

## B. MUST / MUST NOT (id, tag, rule, why with the number)
- M01 [MANUAL] A view MUST read only what it draws; a parent MUST NOT read a field just to pass it on. PF-13/24. Sidebar read the agent list: every update re-ran header, footer, sheets.
- M02 [AUTO C03] MUST NOT build `Binding(get:)` on a store in a parent init/body; the child reads the store. PF-18. ChatScreen + Composer ran on every key.
- M03 [AUTO C04] MUST NOT create controllers/engines/stores in a `@State` default or `State(initialValue:)`. PF-2. 82 to 112 controllers/s, idle at 100 % main.
- M04 [MANUAL] Store setters MUST write only on change (`if a != b { a = b }`), sort into a copy. PF-25. Equal snapshots re-ran the sidebar.
- M05 [MANUAL] MUST NOT assign a tracked struct per event; publish the one drawn value on change. PF-20. Mascot notified readers per key.
- M06 [AUTO C45] MUST NOT use ObservableObject/@Published/@StateObject; use `@Observable`. PF-39. Any change re-runs every reader.
- M07 [MANUAL] Chrome state MUST flip through observable flags (`SurfaceFlags`), never by re-assigning roots/environment or putting closures in it. PF-7/19. 52 to 156 ms settle stall.
- M08 [AUTO C01] `.id(x)` MUST NOT take a value that changes while content streams/types (seqEnd, count, text, UUID, Date); use `rowAnchor`. PF-3. 145 creates/s, 113 hitches.
- M09 [MANUAL] Ids MUST be stable entity ids (`seq:<seqStart>`, agentId), never offsets/`\.self` of structs; an item keeps one slot in the tree across states; each item gets only what is true for it. PF-3/5.
- M10 [AUTO C06] A Row/Cell view MUST NOT store closures: Equatable value + one actions object. PF-4/R-2. Closures are never equal.
- M11 [MANUAL] Repeated items MUST be Equatable by what they draw (not colour tokens), applied with `.equatable()`; no AnyView in repeated content. PF-4/37. Markdown bodies 11 to 25 -> 1 per update.
- M12 [MANUAL] A lazy stack MUST get only what is near the viewport; no `ScrollView{VStack{ForEach}}` over > 30 items; sheet/menu content is built when presented. PF-12/37.
- M13 [AUTO C13] MUST NOT put `GeometryReader` in a ForEach/List; use `onGeometryChange` written on change. PF-30. 8 card kinds.
- M14 [MANUAL] Rows MUST reserve their size before appearing and never change height after. PF-10. Layout shift while scrolling cards.
- M15 [AUTO C08 C09] A body MUST NOT build formatters/regex/coders or call file, Keychain, pasteboard, image-decode APIs. PF-6/16/26. 1 to 2.3 ms per pass.
- M16 [MANUAL] Derived collections (sort/filter/group/Set) MUST be built once per pass in a store or memo, never per row or per keystroke. PF-8/24/26/27.
- M17 [AUTO C47] MUST NOT call `.count` on a suffix inside a scan loop. PF-21. O(n^2): 179 of 949 samples at open.
- M18 [MANUAL] Per-frame/per-token work MUST be O(1) in content size ([hot paths](PATTERNS/hot-paths-and-indexing.md)); parse, highlight, decode, scan that can pass 4 ms MUST be off main or sliced. PF-9/11. Open built 100 pieces in one pass (1.4 s).
- M19 [AUTO C19 C24] `onChange(of:)` MUST NOT take a scanning expression; a body MUST stay <= 150 lines (aim <= 80). PF-8/24.
- M20 [MANUAL] A stream delta MUST change the tail only; settled pieces never rebuild or re-split. PF-5/9. Completion stall 345 -> 138 ms.
- M21 [MANUAL] MUST NOT jump a lazy stack by tens of thousands of points; the open re-seat lands on a real row and ends on the reader's action. PF-12/14/15/29. Blank screens.
- M22 [AUTO C44] MUST NOT retry a rejected option ([DECISIONS.md](DECISIONS.md) D01 to D06). PF-41. Each was measured and failed.
- M23 [AUTO C15] MUST NOT start a `Task` in `.onAppear`; use `.task`/`.task(id:)`. PF-36. Never cancelled.
- M24 [AUTO C17] MUST NOT write `while true`; loops check `Task.isCancelled`. PF-36.
- M25 [MANUAL] Tasks MUST have an owner, be cancelled on disappear/deinit, be keyed by `.task(id:)`, never one per row; concurrency bounded; no `DispatchQueue.main` hop from main-actor code. PF-36.
- M26 [MANUAL] Persistence, encoding, large decoding MUST run off main (serial writer). PF-32. Draft write per key.
- M27 [MANUAL] Hot callbacks (`canPerformAction`, scroll, layout, body) MUST NOT do IPC; cache and refresh by notification. PF-16. `hasImages` round trip.
- M28 [AUTO C20] `NSCache` MUST set `countLimit` and `totalCostLimit`. PF-31.
- M29 [MANUAL] Every cache MUST be bounded by count AND cost, locked if touched off main, keyed as the view keys, evicted on memory warning (images). PF-31.
- M30 [MANUAL] Open stores/streams/subscriptions MUST be bounded (6 recent + busy); no unbounded stream buffers. PF-33.
- M31 [MANUAL] Costly objects (WKWebView, audio engine, UITextView) MUST be lazy or warmed at a chosen idle moment, never in init or the open path. PF-34. WKWebView.init 100 to 700 ms.
- M32 [AUTO C39] MUST register fonts in one `CTFontManagerRegisterFontURLs` call. PF-35. Nine calls before the first frame.
- M33 [MANUAL] Launch work MUST be on the first-frame list (section A) or deferred. PF-35. Cold reflection 550 to 800 ms is the floor.
- M34 [MANUAL] `updateUIView` MUST be idempotent and compare before assigning; representables are Equatable. PF-38. Fit memo, 18 to 25 ms keys.
- M35 [MANUAL] Finger-tracked motion MUST run in UIKit (pan + spring); SwiftUI learns open/closed only. R-3.
- M36 [AUTO C21] Animations MUST come from `Motion` `.resolved(reduceMotion:)`; no literal. R-4.
- M37 [MANUAL] Endless animations/timers/polls MUST stop when obscured, asleep or reduce-motion. PF-36. Drawer drag competed with the crab.
- M38 [AUTO C27 C28 C30] MUST NOT leave `PaseoPerf.diff`, `PerfProbe`, `print`, force unwrap, `try!`, `fatalError`. PF-22/40.
- M39 [AUTO S0] `Tools/style-lint/check.sh` MUST pass (R-4 tokens, `perf-*` rules).
- M40 [MANUAL] A perf-motivated change MUST carry before -> after numbers (3 cold runs, median + range, same script); a baseline MUST NOT grow; a store change needs a test; when measuring is impossible, a complexity argument with a bound plus a test, recorded as `unmeasured, handed to manager` ([MEASURE.md](MEASURE.md)). PF-17/22/23.
- M41 [AUTO C48] MUST NOT materialise every index (`.indices.filter/map`) to find one: it allocates O(n) per call. Search outward from the target (`nearestIndex`) or resolve the index once per store change ([hot paths](PATTERNS/hot-paths-and-indexing.md)). PF-21. Find's hop built an array of every built index on each 100 ms tick.
- M42 [AUTO C49] MUST write an observed flag only on change (`if !x { x = true }`): a literal assignment notifies every reader even when nothing changed ([hot paths](PATTERNS/hot-paths-and-indexing.md)). PF-25. Find's per-step flags re-ran the transcript on every step.

## C. If you are about to ... -> do exactly this
- write a loop over messages/rows: O(n) once, no `count` on suffixes (M17); off main if > 4 ms (M18).
- read an index or a row position from a store collection in a body, a scroll/geometry callback or a tick: O(1)/O(log n)
  only — binary-search an ordered array or resolve it once per store change ([hot paths](PATTERNS/hot-paths-and-indexing.md)) (M18).
- find one built/visible index: search outward from the target, do not build an array of all of them (M41).
- add a formatter/regex/decoder: `static let`, never in a body (M15). add a cache: copy `ProseCache` (M29, [TEMPLATES](TEMPLATES/cache.swift.md)).
- add an animation: a `Motion` token (M36), stop when obscured (M37).
- add a Task/timer: `.task(id:)` or a stored cancellable whose handle you cancel (M23-25, M37); a Task started from a method
  keeps its handle (H30, [hot paths](PATTERNS/hot-paths-and-indexing.md) section 5).
- write an observed flag per step/frame: compare first (`if !x { x = true }`) (M42, M04).
- read a store in a body: only what is drawn (M01); pass values to children; no `Binding(get:)` on it (M02).
- add a row: [TEMPLATES/row.swift.md](TEMPLATES/row.swift.md) (M10, M11). add a store setter: compare first (M04) + a test.
- touch the keyboard/composer/transcript/drawer path: only a listed pattern; otherwise D below.

## D. Never decide alone: ESCALATE, or BLOCKED
- **ESCALATE** = a decision that is not yours. Write every part a pattern covers; leave the part that needs the decision
  in its safest form (or unwritten); add one line to the sign-off: `ESCALATE: <what needs deciding> — <why> — <what you did>`.
  You do not wait for an answer: the lead answers in review, and `VERDICT: DONE WITH ESCALATIONS` is how the report says so
  ([FINAL-CHECK.md](FINAL-CHECK.md)).
- **BLOCKED** = you may not write it at all; report `BLOCKED: <what> — <why>` and stop that part of the work.
- Decisions that are not yours: any visible behaviour change; copy or look change; a new unbounded structure; any baseline
  increase (`baseline.txt`, a budget, a bound); anything in the transcript, composer, shell or keyboard path beyond a pattern
  in [PATTERNS](PATTERNS/); removing or weakening a check, a test, a rule; a `perf-ok:` waiver on an AUTO check; retrying
  anything in [DECISIONS.md](DECISIONS.md); a number you could not measure but claim.
- BLOCKED (not an escalation): changing `windowSize`/`windowStep`, the open re-seat's end condition, the roots assignment,
  keyboard behaviour or the hosting container; an unbounded cache; deleting a test; raising a baseline or budget.
