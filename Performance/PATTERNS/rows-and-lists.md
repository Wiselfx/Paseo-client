# Rows and lists

Rules: PF-4, PF-10, PF-24, PF-26, PF-27, PF-37. MUST: M10, M11, M12, M14, M16. Checks: C06, H03, H04, H05, H19, F02.
A row that is `Equatable` and applied with `.equatable()` skips `body` when its inputs are equal. A stored closure is never equal.

## 1. Value model + one actions object (SidebarWorkspaceRow.swift, W3 sweep)
BAD: `struct WorkspaceRow: View { let workspace: WorkspaceDescriptor; let onOpen: () -> Void; let onArchive: () -> Void }`
GOOD:
```swift
struct SidebarWorkspaceRow: View, Equatable {
    let model: SidebarRowModel            // plain values: Equatable
    let actions: SidebarRowActions        // one object per pass; not part of ==
    nonisolated static func == (left: Self, right: Self) -> Bool { left.model == right.model }
}
// call site: SidebarWorkspaceRow(model: model, actions: actions).equatable()
```
`SidebarDirectoryHost` reads the lists; derived data (`SidebarDerivations`) is built once per pass, not per row.

## 2. Equality by what is drawn (`6a5d058`, `d20e8c3`)
A synthesised `==` over a theme that holds colour values re-created on each call was never true: the optimisation was dead.
```swift
nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.bodySize == rhs.bodySize && lhs.blockSpacing == rhs.blockSpacing && lhs.bodyFont == rhs.bodyFont
        && lhs.codeFont == rhs.codeFont && lhs.headingFonts == rhs.headingFonts     // layout inputs, not colours
}
```
Check it worked: `body=` for the view drops (PaseoPerf.body); a number that does not move means `==` is still false.

## 3. Memoise what a page sorts or filters (`FileListMemo`, W3)
BAD: the files page re-sorted every entry with locale-aware compares on each `@State` write (each alert keystroke).
GOOD: `@MainActor private final class FileListMemo { func visible(_ entries: [...], showHidden:, sort:, build: () -> [...]) -> [...] }`
returns the cached result while entries, toggle and sort key are unchanged. Same shape: `PieceMemo`, `ScrubMemo`.

## 4. Do not build a lookup per row (PF-27)
BAD: `Set(session.agents.map(\.id))` as a computed property read by every schedule row. GOOD: build it once per pass, and only when a row needs it.

## 5. Lazy, not eager (PF-37; overall audit #3, #4, #25)
BAD: `ScrollView { VStack { ForEach(rows) { ... } } }` over a list that can pass 30 items (200 workspace rows mounted; 5 000 diff lines).
GOOD: `LazyVStack`; a collapsed section builds no rows; sheet and menu content is built when presented, not per row. No `AnyView` per block:
use a `@ViewBuilder` switch; ids are stable entity ids, not `\.offset`.

If you remember nothing else:
- A row is a value (Equatable, compared by what it draws) plus one actions object; no closures in row initialisers.
- Sorting, filtering, grouping and lookups are built once per pass in the store or a memo, never in a row.
- Unbounded lists are lazy; verify the `.equatable()` took effect by watching the body count.
