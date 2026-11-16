// features: F01 F02 F07 F09 F17 F18
// Fixture: a settings page that is fine: lazy list, stable ids, derived data from a memo, Motion token.
import SwiftUI

@MainActor private final class GoodListMemo {
    private var entries: [Entry]?
    private var result: [Entry] = []

    func visible(_ entries: [Entry], build: () -> [Entry]) -> [Entry] {
        if let cached = self.entries, cached == entries { return result }
        let built = build()
        self.entries = entries
        result = built
        return built
    }
}

struct GoodPage: View {
    let entries: [Entry]
    @State private var memo = GoodListMemo()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    var body: some View {
        let shown = memo.visible(entries) { entries.sorted { $0.name < $1.name } }
        ScrollView {
            LazyVStack {
                ForEach(shown, id: \.name) { item in
                    Text(item.name)
                }
            }
        }
        .sheet(isPresented: $open) { Text("Details") }
        .onTapGesture {
            withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) { open.toggle() }
        }
    }
}
