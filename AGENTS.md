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
