# Glossary

Each term: definition with its number, and how you see or measure it. Fields are from the `-paseo-perf` window line ([MEASURE.md](MEASURE.md)).

| Term | Definition and number | How measured / seen |
| --- | --- | --- |
| Frame | One screen refresh: 1/60 s on the simulator and most phones, 1/120 s on ProMotion. | `fr=` frames per one-second window (60 is healthy) |
| Frame budget | Time to produce a frame: 16.7 ms at 60 Hz, 8.3 ms at 120 Hz. Body, layout and the Core Animation commit all fit in it. | display link in `PerfMonitor` |
| Hitch | A frame later than 1.5 budgets (> 25 ms at 60 Hz). The user sees a stutter. | `hit=`, `hms=` (ms lost) |
| Dropped frame | A refresh that showed the previous frame again. | `drop=`, `gap=` (longest run; > 3 is visible) |
| Stall | The main thread busy for more than 8 ms in one run-loop wake (layout and commit included). | `stall8=` count, `smax=` longest, `stalls=` with the spans inside |
| Jank | Any hitch or stall a user can feel. Tolerance on scroll, stream, typing, drawer and tap: zero. | the window lines of the scenario |
| Main-thread busy % | Share of the window the main thread was working; > 50 % with nothing happening = a loop; budget at idle < 5 %. | `busy=` |
| Body evaluation | One run of a view's `body`. Target < 1 ms; counted per named view. | `PaseoPerf.body("Name")` -> `body=Name:12` |
| Invalidation | SwiftUI marking a view's body stale because something it read changed (or a non-comparable input like a closure). | `-paseo-perf-changes` -> `perf.why` lines name the key path |
| Identity | What SwiftUI uses to decide "same view": structural position plus `.id`/`ForEach` id. A new identity = destroy and rebuild the subtree. | `md.appear`/`md.disappear` counts |
| Lazy stack realisation | A `LazyVStack` builds a row only when it nears the viewport; before that it estimates heights. A jump leaves rows unbuilt (blank) until a scroll event. | content height jumps; `openpin.fire.h<height>` counters |
| Re-seat | The open-time correction that scrolls a long chat to the real bottom repeatedly until the estimated and real heights agree (`repinOpen`, cap 16). | `openpin.fire`, `openpin.nudge`, `openpin.off.*` |
| Window (turn window) | The newest 16 turns mounted in the transcript; older ones reveal 12 at a time. | `windowSize`, `windowStep` |
| Cold vs warm | Cold: first use in this launch (type metadata, caches empty, process not started). Warm: repeated. Cold costs are paid once per launch. | first run after launch vs later |
| Idle floor | The numbers of a scenario that does nothing, on the same build; every other number is read against it. | `repeat.sh idle "wait 12" 3` |
| Simulator floor | The simulator's own noise: 60 Hz only, shared GPU, accessibility initialisation; one-frame hitches cannot be signed off. | idle windows and the first-tap cost |
| Debug vs Release | Debug has no specialisation or inlining, so SwiftUI is several times slower and conformance lookups dominate; counts and ratios carry over, milliseconds do not. Release is the verdict. | `install` vs `install-release` |
| Hang | A main-thread stall long enough that the app looks frozen (the OS reports about 250 ms and up). Anything over 100 ms on a tap is felt. | `smax=` in hundreds |
| Write on change | Assigning an `@Observable` property only when the new value differs, because the setter notifies even for an equal value. | `body=` of readers at idle |
| Equatable row | A view whose `==` compares what it draws, applied with `.equatable()`, so SwiftUI skips its body when nothing changed. | the row's `body=` count |
| Warm-up / prewarm | Doing a costly first-use step once at a chosen quiet moment (idle, after the open) instead of under the user's finger. | `sp=warm.*` spans |
