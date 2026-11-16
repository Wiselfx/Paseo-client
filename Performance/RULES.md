# Rules (PF-1 to PF-41)

The numbered performance rules, consolidated from `docs/perf/PERFORMANCE-RULES.md` (ids 1 to 27 keep their numbers; 28 to 41 are
new from passes 8 to 11, the W3 sweep and the overall audit). Each row: the requirement, WHY with the number that motivated it,
CHECK (`Cnn` = auto check, `Hnn` = manual heuristic, both in [FINAL-CHECK.md](FINAL-CHECK.md); `M..` = line in [MUST.md](MUST.md)),
FIX PATTERN. Numbers are the Debug simulator's unless marked Release. History: [CATALOG.md](CATALOG.md).

## Observation and invalidation
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-1"></a>PF-1 | Idle is silent: nothing runs when nothing changed. | idle held main at 100 %, 9 to 13 fps; `Shell` body 40 to 190/s | `perf-run.sh idle "wait 10"` prints no window; any `body=` at idle is a loop | [observation](PATTERNS/observation-and-invalidation.md) |
| <a id="pf-2"></a>PF-2 | No side effects in `init`, no object creation in a property default / `State(initialValue:)`. | 82 to 112 `ChatController`s built and dropped per second | C04, M03 | lazy holder, [launch](PATTERNS/launch-and-startup.md) |
| <a id="pf-7"></a>PF-7 | Chrome state flips through observable flags, never by re-assigning roots/environment. | 52 to 156 ms settle stall | H25, M07 | `SurfaceFlags`, [animation](PATTERNS/animation-and-drawer.md) |
| <a id="pf-13"></a>PF-13 | A view reads a flag only if it draws it; the read lives in the child that needs it. | drawer flag read by the sidebar re-ran the directory body per motion | M01 | `SidebarUsageDriver` |
| <a id="pf-18"></a>PF-18 | A parent never builds a `Binding` whose getter reads a store. | `ChatScreen`+`Composer` ran per key (26/window) | C03, H02, M02 | child reads the store |
| <a id="pf-19"></a>PF-19 | A big body does not read a re-created closure/binding just to forward it; gate on a value key. | first focus re-ran sidebar, chat, composer (~220 ms Release) | H25, M07 | `ShellRootsKey` |
| <a id="pf-20"></a>PF-20 | Do not assign a tracked struct on every event. | mascot `handle(.userActivity)` per key notified readers | M05 | `@ObservationIgnored` + `mascotState` on change |
| <a id="pf-24"></a>PF-24 | Read lists in a child, not in the page that owns the chrome. | every agent update re-ran header, footer, sheets | C24, H14, M01 | `SidebarDirectoryHost` |
| <a id="pf-25"></a>PF-25 | An `@Observable` setter always notifies: write only on change; sort into a copy. | repeated snapshots re-ran sidebar; find's per-step flags re-ran the transcript | C49, H16, M04, M42 | [stores](PATTERNS/stores-and-core.md), [hot paths](PATTERNS/hot-paths-and-indexing.md) |
| <a id="pf-39"></a>PF-39 | `@Observable` only: no `ObservableObject`/`@Published`/`@StateObject`. | any change re-runs every reader | C45, M06 | `@Observable` |

## Identity, rows, lists
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-3"></a>PF-3 | View identity follows stable values only; anchors are overlays. | `.id("row:\(seqEnd)")`: 145 creates/s, 113 hitches, worst frame 766 ms | C01, H01, M08; core `StreamingIdentityTests` | `rowAnchor`, [identity](PATTERNS/identity-and-streaming.md) |
| <a id="pf-4"></a>PF-4 | Repeated items are `Equatable` on what they draw and skip `body`; no closures in row inits. | markdown bodies 11 to 25 -> ~1 per update | C06, H03, M10, M11 | [rows](PATTERNS/rows-and-lists.md), [row template](TEMPLATES/row.swift.md) |
| <a id="pf-5"></a>PF-5 | Do not feed one changing fact to every item; keep an item in one tree slot across states. | `isStreaming` flip rebuilt 40 views (345 ms) | M09, M20 | `isStreaming && ref.isTailMarkdown`, `answerProse` |
| <a id="pf-10"></a>PF-10 | Rows are measured before visible: reserve size, never change height after appearing. | layout shift 6300 -> 9100 pt while scrolling cards | M14 | reserve frames |
| <a id="pf-30"></a>PF-30 | Width readers use `onGeometryChange` written on change; no `GeometryReader` per row. | 8 card kinds + tables used GeometryReader | C13, H07, M13 | [media](PATTERNS/media-and-images.md) |
| <a id="pf-37"></a>PF-37 | Unbounded lists are lazy; no `ScrollView{VStack{ForEach}}`; no `AnyView` in repeated content. | sidebar/diff mounted every row (200 rows) | H19, H04, M11, M12 | `LazyVStack`, `@ViewBuilder` switch |

## Work in bodies and callbacks
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-6"></a>PF-6 | No synchronous system call, formatter, regex or coder construction in a body. | `isSourceTypeAvailable` 1 to 2.3 ms per pass | C08, C09, H06, M15 | `static let`, memo |
| <a id="pf-8"></a>PF-8 | Memoise derived structures where used. | 3 splits per delta (reveal writes 4 `@State`) | C19, H05, M16 | `PieceMemo`, `ProseCache` |
| <a id="pf-9"></a>PF-9 | Per-frame and per-token work is O(1) in the content. | `rich.pieces` grew 1 to 3 ms over a reply | H29, M18, M20 | [hot paths](PATTERNS/hot-paths-and-indexing.md) |
| <a id="pf-16"></a>PF-16 | No IPC in a hot callback; cache and refresh by notification. | `hasImages` round trip in `canPerformAction` | C09, M27 | `PasteboardImageState` |
| <a id="pf-21"></a>PF-21 | Scans over message text are O(n); derived indexes are lazy; finding one index must not build every index. | `text[i...].count` per char: 179 of 949 samples; find's hop rebuilt an index array per tick | C47, C48, H29, M17, M41 | `httpSchemeLength`, lazy `mediaIndex`, [hot paths](PATTERNS/hot-paths-and-indexing.md) |
| <a id="pf-26"></a>PF-26 | A page owning text-field state re-evaluates per key: memoise what it sorts/filters; compile regexes once. | files page re-sorted per alert keystroke | H05, M16 | `FileListMemo`, `static let` |
| <a id="pf-27"></a>PF-27 | Do not build a lookup once per row. | `Set(agents.map(\.id))` read by every schedule row | H05, M16, `perf-agents-set-in-view` | once per pass |

## Big content, lazy stacks, scrolling
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-11"></a>PF-11 | Heavy first appearance is a finding: parse/highlight/decode off main or in slices, with reserved space. | open built ~100 pieces in one pass: 1.4 to 1.6 s | M18 | `ProseWarmup`, [text](PATTERNS/text-markdown-code.md) |
| <a id="pf-12"></a>PF-12 | A lazy stack gets only what is near the viewport (window 16/12); open lands on the real bottom. | blank screens, ~100 pieces in one pass | H27, M12, M21 | [lazy stacks](PATTERNS/lazy-stacks-and-scrolling.md) |
| <a id="pf-14"></a>PF-14 | The open re-seat ends when the reader acts (focus, finger, send, find), never on a layout heuristic. | "insets moved" ended it early: blank chat | H27, M21 | `repinOpen` |
| <a id="pf-15"></a>PF-15 | No programmatic jump of tens of thousands of points in a lazy stack. | find step landed blank | H27, M21 | window around target, bounded hops |
| <a id="pf-28"></a>PF-28 | Older turns are not revealed while the open re-seat settles. | window grew to the whole chat: 370 bodies, 2.6 s | M21 | guard on reveal |
| <a id="pf-29"></a>PF-29 | The open re-seat lands on a real row (`scrollTo(id:"bottom")`), not the estimated edge. | content 33k to 48k pt -> 13.5k to 17.8k; stalls 1232/1431 ms gone | C44, M21 | `repinOpen` |

## Concurrency, persistence, caches
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-31"></a>PF-31 | Caches are bounded by count AND cost, locked if touched off main, keyed as the view keys. | evict-all at 64 entries; warm-up filled caches off main | C20, H12, H24, M28, M29 | `ProseCache`, [cache template](TEMPLATES/cache.swift.md) |
| <a id="pf-32"></a>PF-32 | Encode and write off main on a serial queue; coalesce. | draft JSON+disk write per key on main | H17, M26 | `DraftFileWriter` |
| <a id="pf-33"></a>PF-33 | Open conversations/streams are bounded (6 recent + busy). | every chat kept its store and live stream for the session | H18, M30 | `retainedConversationLimit` |
| <a id="pf-36"></a>PF-36 | Tasks, timers, animations have an owner and a visibility gate; `.task(id:)`, cancel on disappear; a Task started from a method keeps its handle. | crab/sweeps competed with drawer drag; panel loaded while closed; find's fetch outlived a close | C15, C17, H08, H09, H10, H30, M23 to M25, M37 | [concurrency](PATTERNS/concurrency-and-main-thread.md), [hot paths](PATTERNS/hot-paths-and-indexing.md) |

## Objects, launch, UIKit
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-34"></a>PF-34 | Costly objects are lazy or warmed at a chosen idle moment, never in init or the open path. | `WKWebView.init` 100 to 700 ms; `VoiceAudioEngine` in every controller init | H22, M31 | `prewarm()` after re-seat, `ComposerWarmup` |
| <a id="pf-35"></a>PF-35 | Launch: nothing blocks the first frame but defaults, one font registration call, the shell. | nine font calls; cold reflection 550 to 800 ms | C39, H23, M32, M33 | [launch](PATTERNS/launch-and-startup.md) |
| <a id="pf-38"></a>PF-38 | `updateUIView` is idempotent: compare before assigning; representables are `Equatable`; memoise sizing. | per-key `sizeThatFits` 18 to 25 ms stalls | H15, M34 | fit memo, [uikit](PATTERNS/uikit-interop-and-keyboard.md) |

## Evidence and hygiene
| ID | Requirement | WHY | CHECK | FIX |
| --- | --- | --- | --- | --- |
| <a id="pf-17"></a>PF-17 | Every perf change carries before -> after (`W1: <what> (<before> -> <after>)`). | a fix without a number is a guess | M40 | [evidence](TEMPLATES/evidence-block.md) |
| <a id="pf-22"></a>PF-22 | The instrument must not cost what it measures; remove probes when the cause is found. | `Mirror` in `diff`: 45 of 110 samples | C27, M38 | [instrumentation](TEMPLATES/instrumentation.md) |
| <a id="pf-23"></a>PF-23 | Read simulator numbers against what drives it (AXe warm-up, keyboard = system). | +100 to 140 ms at first tap; ~340 ms first keyboard | [MEASURE.md](MEASURE.md) | `ui reading` first |
| <a id="pf-40"></a>PF-40 | No `print`, force unwrap, `try!`, `fatalError` left in. | AGENTS rule 5 | C28, C30, M38 | `guard let`, `Logger` |
| <a id="pf-41"></a>PF-41 | Rejected options stay rejected unless new evidence is escalated. | each was measured and failed | C44, M22 | [DECISIONS.md](DECISIONS.md) |

Keeping it true: `Tools/style-lint/check.sh` (the `perf-*` ratchet), `final-check.sh --self-test`, Core test `StreamingIdentityTests`.
