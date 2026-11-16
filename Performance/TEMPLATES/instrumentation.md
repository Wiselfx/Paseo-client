# Instrumentation snippet (`PaseoPerf`, DesignSystem/Perf/PaseoPerf.swift)

Launch with `-paseo-perf` (off by default; one branch per call when off). Names are `StaticString` literals.
```swift
var body: some View {
    let _ = PaseoPerf.body("MyRow")                              // 1. who re-runs, how often (KEEP on hot paths)
    let _ = PaseoPerf.why(Self.self)                             // 2. SwiftUI's reason with -paseo-perf-changes (big views only)
    let _ = PaseoPerf.diff("myrow", [("text", text)])            // 3. TEMPORARY: which input changed (REMOVE)
    PaseoPerf.measure("myrow.parse") { parse(text) }             // 4. time a block you suspect (KEEP on hot paths)
    ...
}
PaseoPerf.count("fit.hit")                                       // event counter (StaticString)
if PaseoPerf.enabled { PaseoPerf.countNamed("openpin.fire.h\(Int(height))") }   // run-time name: always guard
let s = PaseoPerf.begin("name"); defer { PaseoPerf.end(s) }      // span when a closure does not fit
```
Remove before you finish (`final-check.sh` C27 fails on them): `PaseoPerf.diff`, `PerfProbe(`, unguarded `countNamed`, one-off probes, `print`.
`PaseoPerf.body`, `measure`, `count`, `mark` stay. Do not interpolate through `Mirror` or re-run work per hit: the instrument must not cost what it measures (PF-22).
Reading: `body=MyRow:12` per second; `sp=myrow.parse:3x0.9/max0.4`; a stall line names overlapping spans. Window field table: [MEASURE.md](../MEASURE.md).
