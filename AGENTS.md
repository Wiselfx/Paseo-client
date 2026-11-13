# Rules for coding agents

Read `ARCHITECTURE.md` first, then your ticket in `docs/tickets/`.

## Setup

```sh
. ~/.local/share/swiftly/env.sh        # Swift 6.4 toolchain (Linux)
cd Packages/PaseoCore
swift build --build-tests
swift test                             # all tests
swift test --filter TimelineStateTests # one suite
```

There is no Xcode here. `Packages/PaseoUI` and `App/` cannot be compiled on this machine.

## UI rules

These rules (PLAN §1, R-1…R-7) govern every line of UI code. Reviews check them.

- **R-1. Observation is narrow.** A view reads only what it draws. Stores reach a leaf view as
  values or as a narrow `@Observable` child, never as "the whole session". Derived state that costs
  more than O(1) lives in the store, maintained incrementally, never as a computed property read
  from `body`. No `onChange(of:)` on a computed value that scans a collection.
- **R-2. Rows are equatable values.** Transcript turns, sidebar rows, history rows and file rows
  take value inputs plus one actions object from the environment, and conform to `Equatable` so
  SwiftUI skips them when nothing changed. No closures in row initializers.
- **R-3. One owner per gesture surface; finger-tracked motion runs in UIKit.** Anything that tracks
  a finger across the screen (the drawers, the panel) is a UIKit container driven by
  `UIPanGestureRecognizer`, handing off to a velocity-matched
  `UISpringTimingParameters(dampingRatio: 1)`. SwiftUI hosts the content and learns only
  open/closed.
- **R-4. Tokens only.** Colors from `Palette`, fonts from `Typography` (via `Font.paseo(_:)`),
  spacing from `Space`, radii from `Radius`, animations from `Motion` (always
  `resolved(reduceMotion:)`), feedback from `Haptics`. A literal `.font(.system(size:))`,
  `Color(red:)`, `.cornerRadius(n)` or `.animation(.spring…)` outside `DesignSystem/` fails
  review; `Tools/style-lint/style-lint.sh` is the check.
- **R-5. Components before screens.** If two screens need the same thing, it is a component in
  `DesignSystem/Components/`.
- **R-6. No new features in this round.** Behaviour changes only where a plan or ticket says so.
  Upstream copy stays verbatim.
- **R-7. Upstream first.** Paseo upstream (`/home/paseo/dev/paseo-upstream-ref`: `docs/`, `public-docs/`,
  `packages/protocol|server|client|app`) is the specification. Before implementing or changing any
  function, feature, behaviour or performance measure, find how upstream does it and match it (message,
  fields, ordering, capability gating, user-facing words from `i18n/resources/en.ts`); cite
  `Upstream: path:line` in the change. If upstream does not have it, we do not build it. If the daemon
  already answers something, ask it; do not derive it client-side. Do not invent, and do not rebuild what a
  path already provides.
- **Copy.** Sentence case for our own labels; "host" is the user-facing noun ("daemon" only in
  troubleshooting or a command name); never invent copy — keep the existing string or port
  upstream's `en.ts` verbatim.
- **Accessibility.** Every icon-only control has a label, every control has a 44 pt hit area, text
  containers use `minHeight` (not `height`), and all motion goes through `Motion.resolved`.

## Rules

1. **Stay inside your ticket.** Only edit the files it lists. If you think something outside it must
   change, stop and say so in your final message instead of changing it.
2. **Contracts are fixed.** Do not change public signatures, types or doc comments written by the
   ticket author. You may add `private`/`internal` helpers.
3. **Tests are the spec.** Never edit, delete, skip or weaken an existing test. Add your own tests
   in new files.
4. **No new dependencies.** Foundation, Observation and Swift Testing only in PaseoCore, plus `swift-crypto` in PaseoKit (relay encryption only; approved by the user).
5. **No force unwraps or `fatalError`** in your implementation, except where the ticket says so.
6. **No untested platform branches.** Code under `#if os(...)` / `#if canImport(...)` that only
   compiles on Apple platforms is never built here. Avoid such branches; if one is unavoidable,
   keep it tiny and list it in your final message so it gets checked in Xcode.
7. **Swift 6 strict concurrency.** Code must build with no warnings about Sendable or isolation.
8. **Done means:** `swift build --build-tests` has no errors or warnings in your files, and
   `swift test` passes the suites named in your ticket.
9. **Commit** on your branch when done, with a message that names the ticket (for example
   `T2: timeline reducer`). Do not push, merge or rebase.
10. **Final message:** what you did, the test output summary, and anything you were unsure about.
   If you couldn't finish, say exactly what's missing. Don't claim tests pass unless you ran them.
