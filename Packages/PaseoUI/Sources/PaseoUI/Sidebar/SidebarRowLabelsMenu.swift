#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The row's labels submenu: checkmark for assignments, "New label…" to mint one (and assign it) in place.
struct SidebarRowLabelsMenu: View {
    let model: SidebarRowModel
    let actions: SidebarRowActions

    @ViewBuilder var body: some View {
        let workspace = model.workspace
        if model.labelCatalog.isEmpty {
            Text("No labels yet")
        }
        ForEach(model.labelCatalog, id: \.name) { label in
            Button {
                actions.toggleLabel(label, on: workspace)
            } label: {
                HStack(spacing: 8) {
                    WorkspaceLabelDot(color: label.color)
                    Text(label.name)
                    Spacer(minLength: 12)
                    if (workspace.labels ?? []).contains(where: {
                        $0.caseInsensitiveCompare(label.name) == .orderedSame
                    }) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Divider()
        Button("New label…", systemImage: "plus") { actions.newLabel(on: workspace) }
    }
}
#endif
