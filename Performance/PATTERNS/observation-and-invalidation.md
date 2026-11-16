# Observation and invalidation

Rules: PF-1, PF-2, PF-7, PF-13, PF-18, PF-19, PF-20, PF-24, PF-39 ([RULES.md](../RULES.md)). MUST: M01 to M07. Checks: C03, C04, C45, H02, H11, H14.
A body is re-run when anything it *read* changes. Reads are charged to whoever evaluates them, including bindings SwiftUI compares.

## 1. A parent builds a binding that reads a store (PF-18; `7c2802e`, ChatScreen + Composer ran per key)
BAD (ChatComposer.swift, `ComposerView.init`):
```swift
self._text = Binding(get: { store.draft }, set: { store.draft = $0 })   // the parent's body now depends on store.draft
```
GOOD (the child reads and writes the store itself, in its own body):
```swift
private var text: String {
    get { switch mode { case .conversation: store?.draft ?? ""; case .draft(let draft): draft.text } }
    nonmutating set { switch mode { case .conversation: store?.draft = newValue; case .draft(let draft): draft.text = newValue } }
}
private var textBinding: Binding<String> { Binding(get: { text }, set: { text = $0 }) }
```
Result: `ChatScreen` body per key 1 -> 0; per-key stalls 18 to 25 ms -> max 20 ms (Release).

## 2. Object creation in a `@State` default (PF-2; `d4a71cb`, 82 to 112 controllers/s, idle at 100 % main)
BAD: `_controller = State(initialValue: ChatController(session: session, store: store, ...))` runs on every parent pass.
GOOD (ChatScreen.swift): hold a cheap lazy builder; the object is built once, in an observation scope of its own.
```swift
@State private var holder: ChatControllerHolder
_holder = State(initialValue: ChatControllerHolder { ChatController(session: session, store: store, ...) })
// final class ChatControllerHolder { var controller: ChatController {
//     if let built { return built }
//     let controller = withObservationTracking({ make() }, onChange: {}); built = controller; return controller } }
```

## 3. Flip chrome through flags, not roots (PF-7; `9b271ee`, settle stall 52 to 156 -> 10 to 36 ms)
BAD: `sidebarHost.rootView = AnyView(sidebarRoot.environment(\.isSurfaceObscured, sidebarObscured))` at the first and last frame of every motion.
GOOD (ShellDrawer.swift): `@Observable final class SurfaceFlags: @unchecked Sendable { var obscured = false; var panelVisible = false }`, written only on change:
```swift
if sidebarFlags.obscured != sidebarObscured { sidebarFlags.obscured = sidebarObscured }
```

## 4. Gate downstream work on a value key (PF-19; `cf4a5db`, first focus ~220 ms Release)
Env closures and bindings count as changed whenever the environment is re-delivered, so `ShellView.body` re-ran and re-assigned three roots.
```swift
struct ShellRootsKey: Equatable { let session: ObjectIdentifier; let selectedAgentId: String?; /* ... only what the roots are built from */ }
func updateUIViewController(_ controller: ShellContainerController, context: Context) {
    guard controller.rootsKey != rootsKey else { return }
    controller.rootsKey = rootsKey; controller.setRoots(sidebar: sidebar, main: main, panel: panel)
}
```

## 5. Read in the child that draws it (PF-13/24; `b27adb8`, `Sidebar` bodies per motion 1 -> 0)
BAD: `@Environment(\.isSurfaceObscured)` read in `PaseoSidebar` only to start a poll. GOOD: `SidebarUsageDriver`, a `Color.clear` child that reads it and owns the `.task(id:)`.
Same idea: `SidebarDirectoryHost` reads the agent/workspace lists so the header, footer and sheets do not.

## 6. Do not assign a tracked struct per event (PF-20; `2d8aeb9`)
BAD: `var mascot = MascotStateMachine()` assigned `.handle(.userActivity)` on every key, notifying every reader.
GOOD: `@ObservationIgnored var mascot = ...; var mascotState: MascotState = .idle` and `if mascotState != mascot.state { mascotState = mascot.state }`.

If you remember nothing else:
- A view reads only what it draws; a child that needs a store takes the store, never a `Binding(get:)` built by its parent.
- Never build objects in `init`/`@State` defaults; write observed state only when the value changed.
- Flip chrome with a small observable flag object or an Equatable key, never by re-assigning roots or passing closures through the environment.
