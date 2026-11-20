#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Labels (M2.12)
//
// The label catalog (name + color) is owned by `WorkspaceLabelsStore` (`HostSession.labels`) and
// stays live via `workspace.label.update` pushes. Assignments ride on `WorkspaceDescriptor.labels`,
// kept fresh by the directory's `workspace_update` feed and mirrored eagerly from assignment RPC
// responses. Colors come from the shared identity table (`packages/app/src/styles/identity-colors.ts`):
// low-chroma fills plus light/dark foregrounds. Unknown daemon palette names degrade to a neutral dot.

// MARK: - Color system

private let labelFillHex: [String: UInt32] = [
    "violet": 0x7a6aa8,
    "sky": 0x3d7ea6,
    "emerald": 0x388068,
    "orange": 0xa4673a,
    "pink": 0xb05c80,
    "indigo": 0x6a70b8,
    "teal": 0x368080,
    "red": 0xb06260,
    "amber": 0x8f7838,
    "blue": 0x5179b0,
]
private let labelForegroundLightHex: [String: UInt32] = [
    "violet": 0x6d49b5,
    "sky": 0x3d6985,
    "emerald": 0x3e6e5d,
    "orange": 0x845838,
    "pink": 0x974168,
    "indigo": 0x5251c2,
    "teal": 0x3e6d6c,
    "red": 0x9c4243,
    "amber": 0x716239,
    "blue": 0x39649e,
]
private let labelForegroundDarkHex: [String: UInt32] = [
    "violet": 0xa392d5,
    "sky": 0x6aa6ce,
    "emerald": 0x6cae96,
    "orange": 0xcc8f64,
    "pink": 0xd87da3,
    "indigo": 0x9299d5,
    "teal": 0x6cacab,
    "red": 0xd88381,
    "amber": 0xb29d64,
    "blue": 0x7ba1d5,
]
private func hexColor(_ hex: UInt32, opacity: Double = 1) -> Color {
    let red = Double((hex >> 16) & 0xFF) / 255
    let green = Double((hex >> 8) & 0xFF) / 255
    let blue = Double(hex & 0xFF) / 255
    return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
}
func labelKey(_ color: WorkspaceLabelColor) -> String {
    color.rawValue.lowercased()
}
func labelFill(_ color: WorkspaceLabelColor) -> Color {
    if let hex = labelFillHex[labelKey(color)] { return hexColor(hex) }
    return Color(.sRGB, white: 0.55)
}
func labelForeground(_ color: WorkspaceLabelColor, scheme: ColorScheme) -> Color {
    let table = scheme == .dark ? labelForegroundDarkHex : labelForegroundLightHex
    if let hex = table[labelKey(color)] { return hexColor(hex) }
    return Palette.secondaryInk
}
func labelGround(_ color: WorkspaceLabelColor) -> Color {
    labelFill(color).opacity(0.12)
}
func normalizedLabelName(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
// MARK: - Shared bits

/// The dot used in menus and filter rows. Shared across Sidebar files.
struct WorkspaceLabelDot: View {
    let color: WorkspaceLabelColor
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(labelFill(color))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
// MARK: - Sidebar helpers

extension PaseoSidebar {
    /// The catalog as published by the store. Empty while the store loads, or on a daemon
    /// without `features.workspaceLabels` (the store never fills it there).
    var labelCatalog: [WorkspaceLabelDefinition] {
        session.labels.labels
    }

    /// Resolved definitions for a workspace's raw names. Names the catalog doesn't know (or a
    /// catalog that hasn't loaded) still render with the neutral fallback color. The catalog is
    /// read once per directory pass and handed in (`SidebarDerivations.labelCatalog`).
    func labelDefinitions(
        for workspace: WorkspaceDescriptor, catalog: [WorkspaceLabelDefinition]
    ) -> [WorkspaceLabelDefinition] {
        let names = workspace.labels ?? []
        guard !names.isEmpty else { return [] }
        return names.map { name in
            if let known = catalog.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return known
            }
            // A name the catalog doesn't know: render neutrally, never as a guessed color.
            return WorkspaceLabelDefinition(name: name, color: WorkspaceLabelColor("unknown"))
        }
    }

    func isLabelAssigned(_ label: WorkspaceLabelDefinition, on workspace: WorkspaceDescriptor) -> Bool {
        (workspace.labels ?? []).contains {
            $0.caseInsensitiveCompare(label.name) == .orderedSame
        }
    }

    /// Assigns or unassigns; the store mints the catalog entry on first assignment.
    func toggleLabel(_ label: WorkspaceLabelDefinition, on workspace: WorkspaceDescriptor) {
        let assign = !isLabelAssigned(label, on: workspace)
        Task {
            let ok = await session.labels.setAssignment(
                workspaceId: workspace.id, label: label, assigned: assign)
            if !ok {
                showToast(session.labels.actionError ?? "Couldn't change the label.")
            }
        }
    }

    /// The stored filter name, or nil when the filter is inactive. A stored name the catalog
    /// no longer knows (renamed or deleted elsewhere) is treated as "All" instead of hiding
    /// every workspace. When the catalog is still empty (load failed / no labels yet), the raw
    /// name keeps filtering so reopening the app doesn't lose the choice.
    var labelFilterName: String? {
        let trimmed = labelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let catalog = labelCatalog
        if catalog.isEmpty { return trimmed }
        return catalog.first {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }?.name
    }

    /// One label at a time, or every workspace. Raw names compare case-insensitively.
    func matchesLabelFilter(_ workspace: WorkspaceDescriptor) -> Bool {
        guard let filter = labelFilterName else { return true }
        return (workspace.labels ?? []).contains {
            $0.caseInsensitiveCompare(filter) == .orderedSame
        }
    }

    func toggleLabelFilter(_ name: String) {
        let current = labelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        labelFilter = current.caseInsensitiveCompare(name) == .orderedSame ? "" : name
    }
}
#endif
