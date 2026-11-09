# PaseoUI → PaseoCore API audit (R14)

`swiftc -parse` checks syntax but not cross-module symbol resolution: `Packages/PaseoUI` compiles
only on Apple platforms, so a UI that calls `session.agentLifecycle` against a `HostSession` that
never had it (M7e) passes `-parse` and fails in Xcode. This tool closes that gap and can be rerun
before every merge.

## Rerun

```sh
# from the repo root, with a Swift toolchain installed
. ~/.local/share/swiftly/env.sh
cd Packages/PaseoCore
swift build
swift package dump-symbol-graph --minimum-access-level public   # writes .build/out/symbolgraph/
cd ../..
python3 Tools/api-audit/build_index.py Packages/PaseoCore .
python3 Tools/api-audit/check.py .
```

`build_index.py` reads the symbol graphs written by `swift package dump-symbol-graph` under
`Packages/PaseoCore/.build/out/symbolgraph/` (public API of `PaseoProtocol`, `PaseoKit`,
`PaseoStore`) and scans `Packages/PaseoUI/Sources` + `App/Sources` for the internal declarations
those modules make. It writes `Tools/api-audit/api-index.json`; `check.py` scans the same trees
against that index.

Exit code is 1 when an actionable finding exists (anything other than `unknown-type`), 0 otherwise.

## What it reports

- `missing-member` — a member access (`x.foo`) on a value whose type is a PaseoCore or
  PaseoUI/App type, where that type has no such member.
- `missing-static` — `Type.foo` where `Type` has no static member `foo`.
- `missing-case` — `Type.caseOrStatic` on an enum, or `let x: Enum = .case`, where the case does
  not exist.
- `init-labels` / `init-missing-label` — initializer calls whose argument labels match no
  initializer of that type.
- `duplicate-type` — a top-level type name declared at brace depth 0 in more than one place
  (a compile error in one file; a resolution ambiguity across files).
- `unknown-type` — a PascalCase token that resolves to no known type. Informational only: it is
  almost entirely Apple framework types, generic parameters (`Content`, `Subviews`) and external
  package types (`Markdown`, `Document`, `TerminalView`), which the checker deliberately does not
  model.

## Known limits (suppressed by design)

These are structural false-positive families the checker suppresses rather than reports. If you
extend the checker, keep them suppressed:

- **Collection heads are opaque.** A value whose declared/inferred type is `[T]`, `Set<T>`,
  `Dictionary<K,V>` or `T?` is not member-audited: `.map`, `.filter`, `.isEmpty`, `.first`,
  `.count`, `.append` and friends belong to the collection, not to `T`. Element-typed bindings
  (`for x in xs`, `ForEach(xs) { x in`, `xs.map { x in`) are audited against the element type.
- **`Self` is opaque.** `Self.bodyFont` inside a static member cannot be resolved to the enclosing
  type without a type checker.
- **SwiftUI / UIKit / AppKit members are not modeled.** Heads whose type is a local class or
  struct inheriting from an unresolvable (framework) base — representable `Coordinator` classes,
  `NSLayoutManager`/`UIView` subclasses, `ButtonStyle.Configuration`, representable
  `Context.coordinator` — are skipped rather than audited member by member.
- **Enum cases bound by patterns are untyped.** `case .x(let a)` marks `a` unknown inside that
  scope; it is never audited against a guessed type.
- **Cross-file receiver inference is per-file.** A view extension (`extension ClaudeChatView`)
  that uses a property declared in another file of the same type is not linked across files;
  such receivers resolve to nothing and are skipped, never guessed.
