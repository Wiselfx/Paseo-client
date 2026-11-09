#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// Contract for ticket M3c: the "Changes" page of the workspace panel (`WorkspacePanel`).
/// The panel constructs it with exactly these properties; M3c replaces the body.
struct WorkspaceChangesView: View {
    let session: HostSession
    let checkout: CheckoutStore

    var body: some View {
        Text("Changes").font(.system(size: 15)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
