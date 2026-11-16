# CHECKS: what each id means (reference)

Reference, not reading for a small agent: block 0 of `final-check.sh` names the few files to open for a diff. This file
is here so an id in block 2 or 3 has an exact meaning. Engine: `scripts/fc_checks.py`; every check has a bad and a good
fixture under `scripts/fixtures/` and `--self-test` proves both.

## AUTO checks (block 1): exact patterns; a hit is a violation of the MUST item and fails the run
| Id | MUST | Rule | Flags (on changed lines) |
| --- | --- | --- | --- |
| S0 | M39 | R-4, PF | `Tools/style-lint/check.sh`: more hits than `baseline.txt` allows |
| C01 | M08 | PF-3 | `.id(` whose argument has seqEnd, UUID(), Date, hashValue, .count, .text, .length |
| C03 | M02 | PF-18 | `Binding(get:)` reading store/draft/controller/session inside an `init` |
| C04 | M03 | PF-2 | `@State x = Foo...Controller/Engine/Store/Session/Monitor/Service/Manager/Client(` or `State(initialValue: Foo...(` (App structs excluded) |
| C06 | M10 | PF-4 | closure-typed stored property in a `*Row`/`*Cell` View |
| C08 | M15 | PF-6 | `DateFormatter()`, `NumberFormatter()`, `NSRegularExpression(`, `JSONDecoder()`, `NLTagger(` ... inside a body |
| C09 | M15 | PF-6/16 | `UIImage(data:)`, `Data(contentsOf:)`, `FileManager.default`, `SecItem*`, `UIPasteboard.general` ... inside a body |
| C13 | M13 | PF-30 | `GeometryReader` inside `ForEach`/`List` |
| C15 | M23 | PF-36 | `Task {` inside `.onAppear` |
| C17 | M24 | PF-36 | `while true` with no break/return/throw/cancellation check |
| C19 | M19 | PF-8 | `.onChange(of:)` on `.filter/.sorted/.reduce/.joined/.reversed/.contains(where:)` |
| C20 | M28 | PF-31 | `NSCache<` in a file lacking `countLimit` or `totalCostLimit` |
| C21 | M36 | R-4 | `withAnimation { }` or `withAnimation(.literal)` |
| C24 | M19 | PF-24 | a `body` longer than 150 lines |
| C27 | M38 | PF-22 | `PaseoPerf.diff(`, `PerfProbe(`, unguarded `PaseoPerf.countNamed(` |
| C28 | M38 | PF-40 | `print(`, `debugPrint(`, `dump(`, `NSLog(` |
| C30 | M38 | AGENTS-5 | `x!`, `try!`, `as!`, `fatalError(` (IUO types in signatures excluded) |
| C39 | M32 | PF-35 | `CTFontManagerRegisterFontsForURL` |
| C44 | M22 | PF-41 | `shouldRasterize = true`; window size/step <= 8; NLTagger or `becomeFirstResponder()` in warm-up code; `scrollTo(edge: .bottom)` in `repinOpen` |
| C45 | M06 | PF-39 | `ObservableObject`, `@Published`, `@StateObject`, `@EnvironmentObject`, `@ObservedObject` |
| C47 | M17 | PF-21 | `[i...].count`, `.dropFirst(n).count` |
| C48 | M41 | PF-21 | `.indices.filter/map/compactMap/sorted`, `.enumerated().filter/map` — an array of every index per call |
| C49 | M42 | PF-25 | `<controller/store/session/draft/model>.<flag> = true/false` or `self.<flag> = true/false` in an `@Observable`, inside a `func`, with no compare in the same `if`/`guard` (`updateUIView` excluded: H15 owns it) |

A waiver is `// perf-ok: Cnn <reason of at least 7 chars>` on the flagged line or the line above. It moves the hit to block 4,
and every waiver needs an `ESCALATE:` line. A waiver is a decision, not a fix: do not use it to avoid a one-line guard.

## MANUAL heuristics (block 3): a question with file:line, never a failure
Each id states what to verify. `final-check.sh` prints that sentence once, then at most three locations (`+N more`).

| Id | MUST | What to verify |
| --- | --- | --- |
| H01 | M09 | `.id`/ForEach id is a stable entity id (`seq:<seqStart>`, agentId) that survives every state of the item, not an offset or a streaming value |
| H02 | M01 | `Binding(get:)` reading a store in a body: does the parent now depend on that field for nothing? |
| H03 | M11 | A Row/Cell view not `Equatable`: its body runs for every parent pass |
| H04 | M11 | `AnyView` in repeated content: the child is rebuilt instead of compared |
| H05 | M16 | sort/filter/map over a store collection in a body or computed property: built once per pass (store or memo), not per row or keystroke |
| H06 | M18 | a costly constructor or default read in a body: build it once (`static let`/memo) and pass it in |
| H07 | M14 | `GeometryReader`: each row reserves its size and reads width with `onGeometryChange` written on change |
| H08 | M25 | `DispatchQueue.main` hop from main-actor code: it only delays the work a runloop turn |
| H09 | M25 | Task/`.task` lifecycle: keyed by `.task(id:)`, cancelled on disappear, never one per row |
| H10 | M37 | timer/display link/endless animation: stops when obscured, asleep, or reduce-motion is on |
| H11 | M01 | `onChange(of:)` on a whole collection: every element change re-runs the action |
| H12 | M29 | dictionary cache with no limit or eviction in this file: what bounds its count and cost? |
| H14 | M01 | many `@Environment` reads on one View: each is a dependency of every change to it; read it in the child that draws it |
| H15 | M34 | representable update: `Equatable`, and every assignment compares first |
| H16 | M04 | store property written without a compare, or sorted in place: can the value repeat (push, poll, reconnect)? |
| H17 | M26 | file I/O on a main-actor type: can it move to a serial queue with a value snapshot? |
| H18 | M30 | unbounded stream buffer: use `.bufferingNewest(n)` |
| H19 | M12 | `ScrollView { VStack { ForEach } }` over more than 30 items must be lazy or windowed |
| H20 | M18 | mask/blur/shadow/drawingGroup in repeated content: an offscreen pass per row |
| H21 | M18 | image loaded outside the media pipeline: decode at the drawn size, off main |
| H22 | M31 | a web view outside `Rich/`: lazy or warmed at idle, never in init or the open path |
| H23 | M33 | launch-path work in an init: only defaults, one font call, the shell |
| H24 | M29 | `@unchecked Sendable` with no lock in this file: what protects it? |
| H25 | M07 | closure literal in the environment: a non-comparable value re-runs every reader |
| H26 | M35 | `DragGesture`: finger-tracked motion belongs in a UIKit pan |
| H27 | M21 | transcript scroll/window code: real row id, bounded hops, re-seat ends on the reader's action |
| H28 | M40 | a Core store source changed and no test file did: does the store change need a test? |
| H29 | M18 | a linear scan in a helper: is it reachable from a body pass, a scroll/geometry callback or a tick? Then O(log n) or resolved once (or say it is one-shot) |
| H30 | M25 | a `Task` started from a method with no stored handle: can a newer call, a close or a disappear supersede it? |
| H31 | M18 | a dictionary written from a geometry/scroll callback: a per-frame report overwrites one value and compares first |

## Features (F01 to F19) and paths
Features pull in MANUAL items from the changed lines; path tags pull in the items a file type can affect (transcript, row,
composer, shell, media, store, launch, lists) plus M18 for any UI/Core file. `FEATURES`, `PATH_ITEMS`, `HOT_TAGS` and the
pattern mapping live in `scripts/fc_checks.py`; `--self-test` proves every feature is detected and every item is reachable.

## Self-test and CI
`Performance/scripts/final-check.sh --self-test` runs every check on `scripts/fixtures/bad` (each `// expect: Cnn` /
`// hit: Hnn` marker must match exactly) and `fixtures/good` (must be silent), checks that every MANUAL item has a full
entry in MANUAL.md, that docs links resolve, that the sign-off prints each rule whole, and that the three verdicts parse.
CI runs it, and the changed-files check, on every pull request. Add a check = add a fixture line on each side.
