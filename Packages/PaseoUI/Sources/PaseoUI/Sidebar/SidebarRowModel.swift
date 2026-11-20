#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Everything a workspace row draws, as plain values (R-2): the row skips its body when this is
/// equal. Built per realized row from the directory pass's shared `SidebarDerivations`.
struct SidebarRowModel: Equatable {
    let workspace: WorkspaceDescriptor
    let title: String
    let statusKind: StatusDot.State
    let selected: Bool
    let attention: Bool
    let manuallyUnread: Bool
    let hidden: Bool
    /// The most recently active agent of the workspace; a tap opens it.
    let firstAgentId: String?
    let branchText: String
    /// The compact age ("5m"), nil without an activity stamp.
    let ageText: String?
    let showBranch: Bool
    let showDiffStats: Bool
    let showPRBadge: Bool
    let labelDefinitions: [WorkspaceLabelDefinition]
    let scriptDots: [SidebarScriptDot]
    let scriptDotsLabel: String
    let supportsPinning: Bool
    let supportsLabels: Bool
    let labelCatalog: [WorkspaceLabelDefinition]
}
#endif
