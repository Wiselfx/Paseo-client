#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One date bucket in the "Date" sidebar grouping: today / yesterday / earlier by last activity.
struct SidebarDateBucket: Identifiable {
    let id: String
    let title: String
    let workspaces: [WorkspaceDescriptor]
}
#endif
