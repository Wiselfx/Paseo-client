# Cancellation-safe task loop (shapes of SidebarUsageDriver and MascotDriver)

Owned by a view: key it on the facts that start and stop it; SwiftUI cancels it on disappear and on id change.
```swift
.task(id: "\(isEnabled)|\(isSupported)|\(isSurfaceObscured)|\(scenePhase)") { await poll() }

private func poll() async {
    guard isEnabled, isSupported, !isSurfaceObscured, scenePhase == .active else { return }   // visibility gate
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }                                              // check again after the sleep
        await refresh()
    }
}
```
Owned by an object: store the Task and cancel it in teardown.
```swift
private var loader: Task<Void, Never>?
func start() { loader?.cancel(); loader = Task { [weak self] in await self?.run() } }
deinit { loader?.cancel() }
```
Never: `.onAppear { Task { ... } }` (C15), `while true` (C17), a Task per row, an unkeyed `.task { }` whose closure reads a changing value, a `DispatchQueue.main` hop from main-actor code.
Event closures (Button, `.onChange`) may start a one-shot `Task`; keep the handle if it can outlive the action.
