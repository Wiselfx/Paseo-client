# Hot paths: index lookups, per-tick work, owned tasks

Rules: PF-9, PF-21, PF-25, PF-36. MUST: M18, M25, M41, M42. Checks: C48, C49, H29, H30, H31.
Worked example: the find-in-chat pass (`23ac405` -> `040f0be`), which the framework missed on its first real run.

Everything here has one test: **what does this run per body pass, per scroll/geometry callback, or per tick?** A frame is 8.3 ms at
120 Hz and 16.7 ms at 60 Hz, and the main thread must finish its update before the commit deadline of that frame
([Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)).
Apple flags a view body over 500 us (orange) and over 1000 us (red) in Instruments
([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)),
which is where MUST.md section A's "body < 1 ms" comes from. A loop that scans the conversation in an accessor is
therefore not "cheap because it is only a loop": it is O(n) inside a budget measured in microseconds.

## 1. An accessor read per pass is O(1) or O(log n) — never O(n)
BAD (`FindNavigation.firstTurnIndex`, before):
```swift
turns.firstIndex { ($0.lastRowSeq ?? Int.min) >= seq }   // O(n) on every window-start read: body pass + every scroll frame
```
GOOD (same function, after; test `FindNavigationIndexTests.binarySearchMatchesTheLinearScanOnTimelineOrder`):
```swift
public static func firstTurnIndex(endingAtOrAfter seq: Int, in turns: [Turn]) -> Int? {
    var low = 0
    var high = turns.count
    while low < high {
        let middle = low + (high - low) / 2
        if (turns[middle].lastRowSeq ?? Int.min) >= seq { high = middle } else { low = middle + 1 }
    }
    return low < turns.count ? low : nil
}
```
The binary search is valid only because turns are in timeline order (`lastRowSeq` is non-decreasing) — state that
invariant in the doc comment and pin it with a test that compares against the linear scan on duplicates and ties.
If the array is not ordered, build the index once per store change instead.

H29 asks this question for any helper or computed property that scans a collection rooted at `store.`, `all`,
`turns`, `messages`, ... . It stays MANUAL on purpose: reachability from a body or a tick is not decidable from one
file.

## 2. A per-tick lookup searches outward; it does not build an array
BAD (`ChatTranscript` hop closure, before; runs on each jump tick):
```swift
let built = all.indices.filter { scrollTrack.visibleTurnIds.contains(all[$0].id) }   // O(n) array + closure per element
return FindNavigation.hopTarget(targetIndex: target, builtIndices: built)
```
GOOD (`FindNavigation.nearestIndex`; test `nearestIndexMatchesTheArgminOverAscendingBuiltIndices`):
```swift
public static func nearestIndex(to target: Int, count: Int, where isBuilt: (Int) -> Bool) -> Int? {
    guard (0..<count).contains(target) else { return nil }
    for distance in 0..<count {
        let below = target - distance
        if below >= 0, isBuilt(below) { return below }
        let above = target + distance
        if distance > 0, above < count, isBuilt(above) { return above }
    }
    return nil
}
// caller: FindNavigation.hopTarget(targetIndex: target, builtIndices: [built]) — the hop only ever starts from one turn
```
A tie goes to the lower index, exactly as the ascending-list argmin did; the test proves the hop from the nearest
index equals the hop from the whole built list. C48 fails the array-building form.

## 3. The cheap condition runs before the expensive one
`revealOlderTurnsIfNeeded` reads `metrics.distanceFromTop` (O(1)) before `hiddenTurnCount` (which resolves the window
start): most scroll frames are nowhere near the top, so the lookup never runs on them. Every condition is a pure
read; only the order changed (`040f0be`). Do not reorder conditions that have side effects.

## 4. Compare before writing an observed flag
BAD (per find step; `@Observable` notifies even for an equal value):
```swift
controller.isFollowing = false
controller.anchoringToAnswer = false
controller.find.moved = true
```
GOOD:
```swift
if controller.isFollowing { controller.isFollowing = false }
if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
if !controller.find.moved { controller.find.moved = true }
```
Apple's Instruments guidance is the same for geometry: test whether the change is bigger than a threshold before
updating layout (`onGeometryChange` in *Understanding and improving SwiftUI performance*), and `@Observable` tracks the
properties a view reads — a write to a whole array or a flag re-runs every reader
([Optimize SwiftUI performance with Instruments, WWDC25](https://developer.apple.com/videos/play/wwdc2025/306)).
C49 fails a literal bool write through `controller`/`store`/`session`/`draft`/`model` (or `self` in an `@Observable`)
with no compare in the same `if`/`guard`.

## 5. A task started from a method needs an owner
BAD (fetch started inside `scrollToMatch`; closing find left it running):
```swift
Task { ... await store.loadTimelineWindow(aroundSeq: jump.seq) ... }
```
GOOD (`TranscriptJumpRunner`):
```swift
private var fetch: Task<Void, Never>?
func runAfterFetch(_ work: @escaping @MainActor () async -> Void) { fetch?.cancel(); fetch = Task { @MainActor in await work() } }
func cancel() { cancelRun(); fetch?.cancel(); fetch = nil }        // closing find or the rail
// and in the work: guard !Task.isCancelled else { return } after its own await
```
Cancelling a task does not stop a closure that is already waiting, so the closure re-checks `Task.isCancelled` after
its await. H30 asks this for a discarded `Task {` inside a method; `.task(id:)` remains the first choice for a view.

A per-frame callback should overwrite a value, not keep a table: `FindRowProbe` went from
`frames[seqEnd] = frame` (a dictionary write plus hashing on every geometry change) to
`lastReport = (seqEnd, frame)` with a compare-first write. One match is on screen at a time, so one slot is enough.
If the key really is per item (a height or offset per turn), keep the table but compare the old value before writing it,
and say which bound keeps it small. H31 asks this for a dictionary written from a helper called by
`onGeometryChange`/`GeometryReader` in the same file; a helper in another file is not detectable — say so when you tick M18.

## What stays manual
- Whether a helper is reachable from a body, a scroll callback or a tick (H29 is a question, not a failure).
- Whether a scan runs once per user action (then it is fine; answer M18 with that).
- A dictionary write behind a helper in another file (H31 sees one file).
- Allocation inside closures that are not named (`map`, `compactMap`, `Array(...)`), and whether a closure can be
  hoisted out of a per-frame path.

Before -> after for this pass: code-read only, **unmeasured** (no gate in the session); the change is O(n) -> O(log n)
for the window start, O(n) allocation -> O(distance) for the hop, and one dictionary slot instead of a growing table.
Tests: `FindNavigationIndexTests` (Core). Recorded in [CATALOG.md](../CATALOG.md) J36 to J40.

If you remember nothing else:
- Anything reachable per pass/frame/tick is O(1) or O(log n): binary-search an ordered array or index once per store change.
- Do not materialise an index array to look one up; search outward from the target (C48).
- Compare before writing a flag (C49); own and cancel a task started from a method (H30); one report slot per callback (H31).
