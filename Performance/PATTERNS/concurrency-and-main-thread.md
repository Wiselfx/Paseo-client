# Concurrency and main thread

Rules: PF-6, PF-32, PF-36. MUST: M15, M23, M24, M25, M26. Checks: C08, C09, C15, C17, H08, H09, H17, F05, F11, F12.

## 1. Persistence off main (`d061427`; one serial writer, snapshot on main)
BAD: `JSONEncoder().encode(records)` and `data.write(to:, options: .atomic)` inside the setter path of a keystroke.
GOOD (DraftStore.swift):
```swift
private func write(wait: Bool) {
    let file = StoredFile(drafts: records, formPreferences: formPreferences, lastScreen: lastScreen)   // value copies on main
    Self.writer.write(file, to: fileURL, wait: wait)                                                   // encode + write on the queue
}
private final class DraftFileWriter: Sendable { private let queue = DispatchQueue(label: "paseo.draftstore.write", qos: .utility)
    func write(_ file: DraftStore.StoredFile, to url: URL, wait: Bool) { /* wait ? queue.sync : queue.async */ } }
```
Writes coalesce (`persistInterval`), the first change goes out at once, `flush()` waits (app to background).

## 2. A poll lives in a keyed task that checks cancellation (`b27adb8`)
```swift
.task(id: "\(showUsage)|\(session.hostUsage.isSupported)|\(isSurfaceObscured)|\(scenePhase)") { await poll() }
private func poll() async {
    guard showUsage, session.hostUsage.isSupported, !isSurfaceObscured, scenePhase == .active else { return }
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(HostUsageStore.automaticPollInterval))
        guard !Task.isCancelled else { return }
        _ = await session.hostUsage.load(forceRefresh: false)
    }
}
```
BAD: `.onAppear { Task { while true { ... } } }`: never cancelled, never gated. Panel work follows `isPanelVisible` (`6e53ffa`); the mascot ticker stops once asleep. Template: [task](../TEMPLATES/task.swift.md).

## 3. Warm-ups: detached, cancel-checked, same cache keys (`9f14d48`)
`Task.detached(priority: .userInitiated) { await warm(texts:...) }`, each loop checks `Task.isCancelled`, newest first, nothing awaited by the caller.

## 4. Bodies: no construction, no IO (PF-6, M15)
BAD: `let f = DateFormatter()` / `NSRegularExpression(pattern:)` / `Data(contentsOf:)` in a body. GOOD: `static let`, a memo, or `PaseoDate.parse` (cached; `b368d48`, `855a74b`).
Event closures (Button, `.task`, `.onChange`) are not bodies: the check ignores them, but the main-actor rule still applies (M26).

## 5. Do not hop what is already main
`DispatchQueue.main.async` from main-actor code only delays the work a runloop turn. From a non-main callback use `Task { @MainActor in }` or `MainActor.assumeIsolated` with the notification's `queue: .main`.

If you remember nothing else:
- Anything that writes, encodes or decodes more than a few KB goes to a serial queue with a value snapshot taken on main.
- Every Task has an owner and `.task(id:)`/cancel; loops test `Task.isCancelled`; polls are gated on visibility.
- A body constructs nothing and calls nothing that waits.
