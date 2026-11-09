#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// Contract for ticket M3b: the "Files" page of the workspace panel (`WorkspacePanel`).
/// The panel constructs it with exactly these properties; M3b replaces the body.
struct WorkspaceFilesView: View {
    let checkout: CheckoutStore

    var body: some View {
        Text("Files").font(.system(size: 15)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
