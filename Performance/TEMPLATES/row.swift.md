# New Equatable row (shape of SidebarWorkspaceRow, Sidebar/SidebarWorkspaceRow.swift)

```swift
/// Everything the row draws, as plain values (R-2): the row skips its body when this is equal.
struct ThingRowModel: Equatable {
    let id: String
    let title: String
    let selected: Bool
    let ageText: String?
}

/// What the row can do. One object per pass, shared by every row; not part of equality.
@MainActor
final class ThingRowActions {
    private let owner: ThingList
    init(owner: ThingList) { self.owner = owner }
    func open(_ id: String) { owner.onSelect(id) }
}

struct ThingRow: View, Equatable {
    let model: ThingRowModel
    let actions: ThingRowActions
    nonisolated static func == (left: Self, right: Self) -> Bool { left.model == right.model }

    var body: some View {
        let _ = PaseoPerf.body("ThingRow")
        Button { actions.open(model.id) } label: { Text(model.title).font(.paseo(.callout, weight: .medium)) }
    }
}

// call site, in a lazy container, ids are entity ids:
LazyVStack { ForEach(models, id: \.id) { ThingRow(model: $0, actions: actions).equatable() } }
```
Checklist: no closure stored in the row (C06); `==` compares what is drawn, not colour tokens or objects; the model is built once per pass from derived data, not per row;
the row's `body=` count stays 0 when nothing it draws changed (verify with `-paseo-perf`). Min hit area 44 pt, tokens for fonts/colours (R-4).
