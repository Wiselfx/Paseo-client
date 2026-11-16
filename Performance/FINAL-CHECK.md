# FINAL-CHECK: the mandatory last step for any change in Packages/PaseoUI, Packages/PaseoCore or App/

`final-check.sh` is a small, reliable test, not an oracle. It **guarantees** only the AUTO-VERIFIED list (exact patterns on your
changed lines). It **never claims** anything about timing or semantics: those are the MANUAL block, which you answer by hand.

## Steps (binary; no judgement needed except where a table below makes the call)
0. Keep [MUST.md](MUST.md) open while you code; before you report, re-read its section A. Commit (or stage) your work, then run
   `Performance/scripts/final-check.sh` (base defaults to `origin/main`, else `foundation`; or pass `<base-ref>`).
1. **Block 2 (AUTO-FAILED) must be empty.** Fix each hit with the PATTERNS file it names. No waivers unless escalated (below).
2. **Block 3 (MANUAL)**: for every `[Mnn]` answer yes/no from the diff. "No" or "unsure" -> do the "if no or unsure" line.
   Entries come from the paths and features in your changed lines plus heuristic hits (with file:line). Full text: [MANUAL.md](MANUAL.md).
3. **Evidence**: if the last line says `measure: REQUIRED`, follow [MEASURE.md](MEASURE.md) and paste the
   [evidence block](TEMPLATES/evidence-block.md). Otherwise this output is the evidence.
4. **Report**: paste block 4 (SIGN-OFF) into your final message, tick every `[ ]` with a one-clause reason (`[x] M16 sort is in FileListMemo`)
   or write `ESCALATE: why`. **Done = block 2 empty AND every line ticked or escalated.** Then add the verdict line:
   `VERDICT: DONE (auto-failed=0, manual=N ticked, escalations=K)`.

## What you may decide alone / what you must escalate
| You may decide alone | Escalate to the lead (write `ESCALATE:`) |
| --- | --- |
| Fix an AUTO hit with the named pattern | Any visible behaviour, copy or look change |
| Answer a MANUAL item "yes" with a reason from your diff | A MANUAL item you answered "no" and cannot fix with its stated action |
| Add an `Equatable` row, a `static let`, a compare-before-write, a test | Any new cache/stream/store without count AND cost bound |
| Remove a probe, a `print`, a force unwrap | Any baseline increase (`baseline.txt`, a budget, a limit) |
| Pick a documented option from [DECISION-TREES.md](DECISION-TREES.md) | Touching transcript, composer, shell or keyboard code beyond a pattern in [PATTERNS](PATTERNS/) |
| | Any `perf-ok:` waiver on an AUTO check; removing or weakening a check/test; retrying a [DECISIONS.md](DECISIONS.md) item |

A waiver is `// perf-ok: Cnn <reason of at least 7 chars>` on the flagged line or the line above. It moves the hit from block 2 to the
WAIVERS list, and every waiver needs an `ESCALATE:` line. Heuristic (`Hnn`) hits can be answered in the sign-off or waived the same way.

## Auto checks (block 1): exact patterns; a hit is a violation
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

## Manual heuristics (block 3 hits with file:line): may be false positives, so never failures
H01 id or `ForEach id: \.self/\.offset` not obviously stable (M09) | H02 `Binding(get:)` on a store in a body (M01) | H03 `*Row` View not Equatable (M11) |
H04 `AnyView` (M11) | H05 collection chain in a body or view computed property (M16) | H06 `Calendar.current`, `AttributedString(`, `UserDefaults.standard`, `UIImage(named:)` in a body (M18) |
H07 `GeometryReader` outside ForEach (M14) | H08 `DispatchQueue.main` hop (M25) | H09 `Task` in a body, stored `Task` without `.cancel()`, `.task` without id (M25) |
H10 Timer / CADisplayLink / `TimelineView(.animation)` / `.repeatForever` (M37) | H11 `onChange(of:)` on a collection or `.map` (M01) | H12 dictionary cache with no limit word (M29) |
H13 `withAnimation` in transcript/row/media/shell code (M37) | H14 body of 81 to 150 lines, or 7+ `@Environment` reads (M01) | H15 representable not Equatable / unguarded `updateUIView` assign (M34) |
H16 store property assigned without compare, in-place `sort` (M04) | H17 file I/O in a main-actor type (M26) | H18 `.unbounded` (M30) | H19 `ScrollView{VStack{ForEach}}` (M12) |
H20 `.mask/.blur/.shadow/.drawingGroup` in hot code (M18) | H21 `AsyncImage`, `UIImage(data:)` outside a body (M18) | H22 `WKWebView(` outside `Rich/` (M31) | H23 App init doing I/O (M33) |
H24 `@unchecked Sendable` with no lock in file (M29) | H25 closure literal in `.environment` (M07) | H26 `DragGesture` (M35) | H27 transcript scroll/window code (M21) | H28 store changed, no test changed (M40).

Features that pull in MANUAL items (F01 to F18: observation, lists, text input, media, async, timers, caches, representables, animation,
stores, JSON, file/Keychain, web views, gestures, text rendering, launch, identity, sheets/menus) are defined in `scripts/fc_checks.py`
(`FEATURES`); `--self-test` proves each is detected.

## Self-test and CI
`Performance/scripts/final-check.sh --self-test` runs every check on `scripts/fixtures/bad` (each `// expect: Cnn` / `// hit: Hnn` marker must
match exactly) and `fixtures/good` (must be silent), checks that every MANUAL item has a full entry in MANUAL.md and that docs links resolve.
CI runs it, and the changed-files check, on every pull request. Add a check = add a fixture line on each side.
