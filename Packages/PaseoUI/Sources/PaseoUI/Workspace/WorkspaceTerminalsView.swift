#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// Contract for ticket M3d: the "Terminal" page of the workspace panel (`WorkspacePanel`).
/// The panel constructs it with exactly these properties; M3d replaces the body.
struct WorkspaceTerminalsView: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor

    var body: some View {
        Text("Terminal").font(.system(size: 15)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
