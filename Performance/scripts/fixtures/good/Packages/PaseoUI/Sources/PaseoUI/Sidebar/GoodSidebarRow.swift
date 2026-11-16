// features: F02 F17
// Fixture for final-check --self-test. GOOD code: copied in shape from SidebarWorkspaceRow (R-2): a value model,
// one actions object, Equatable on the model only, applied with .equatable(). Must produce no finding at all.
import SwiftUI

struct GoodRowModel: Equatable {
    let title: String
    let selected: Bool
    let ageText: String?
}

@MainActor
final class GoodRowActions {
    func open(_ id: String) {}
}

struct GoodWorkspaceRow: View, Equatable {
    let model: GoodRowModel
    let actions: GoodRowActions

    nonisolated static func == (left: Self, right: Self) -> Bool { left.model == right.model }

    var body: some View {
        Button {
            actions.open(model.title)
        } label: {
            Text(model.title)
        }
    }
}

struct GoodDirectory: View {
    let models: [GoodRowModel]
    let actions: GoodRowActions

    var body: some View {
        LazyVStack {
            ForEach(models, id: \.title) { model in
                GoodWorkspaceRow(model: model, actions: actions).equatable()
            }
        }
    }
}
