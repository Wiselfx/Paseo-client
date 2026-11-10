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

private func labelKey(_ color: WorkspaceLabelColor) -> String {
    color.rawValue.lowercased()
}

private func labelFill(_ color: WorkspaceLabelColor) -> Color {
    if let hex = labelFillHex[labelKey(color)] { return hexColor(hex) }
    return Color(.sRGB, white: 0.55)
}

private func labelForeground(_ color: WorkspaceLabelColor, scheme: ColorScheme) -> Color {
    let table = scheme == .dark ? labelForegroundDarkHex : labelForegroundLightHex
    if let hex = table[labelKey(color)] { return hexColor(hex) }
    return Palette.secondaryInk
}

private func labelGround(_ color: WorkspaceLabelColor) -> Color {
    labelFill(color).opacity(0.12)
}

private func normalizedLabelName(_ name: String) -> String {
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

/// The chip on the row meta line: the name in its identity foreground on its own 10% tint.
private struct WorkspaceLabelChip: View {
    let label: WorkspaceLabelDefinition

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label.name)
            .font(.paseo(.caption2, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(labelForeground(label.color, scheme: colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(labelGround(label.color), in: .capsule)
            .accessibilityLabel("Label: \(label.name)")
    }
}

/// One swatch in the ten-color palette rows.
private struct LabelColorSwatch: View {
    let color: WorkspaceLabelColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(labelFill(color))
                .frame(width: 22, height: 22)
                .overlay {
                    if selected {
                        Circle()
                            .stroke(Palette.ink, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(color.rawValue)")
        .accessibilityValue(selected ? "Selected" : "")
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
    /// catalog that hasn't loaded) still render with the neutral fallback color.
    func labelDefinitions(for workspace: WorkspaceDescriptor) -> [WorkspaceLabelDefinition] {
        let names = workspace.labels ?? []
        guard !names.isEmpty else { return [] }
        let catalog = labelCatalog
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

    // MARK: Row meta line

    /// Up to two chips, then "+N". Low emphasis; reading priority sits with the branch and
    /// status, labels come after them.
    @ViewBuilder func labelChips(for workspace: WorkspaceDescriptor) -> some View {
        let defs = labelDefinitions(for: workspace)
        if !defs.isEmpty {
            let shown = Array(defs.prefix(2))
            HStack(spacing: 4) {
                ForEach(shown, id: \.name) { label in
                    WorkspaceLabelChip(label: label)
                }
                if defs.count > shown.count {
                    let extra = defs.count - shown.count
                    Text("+\(PaseoFormat.integer(extra))")
                        .font(.paseo(.caption2, weight: .medium))
                        .foregroundStyle(Palette.captionInk)
                        .accessibilityLabel("\(extra) more labels")
                }
            }
        }
    }

    // MARK: Context menu

    /// The labels submenu on a workspace row: checkmark for assignments, "New label…" to mint
    /// one (and assign it) in place.
    @ViewBuilder func labelsSubmenu(for workspace: WorkspaceDescriptor) -> some View {
        let catalog = labelCatalog
        if catalog.isEmpty {
            Text("No labels yet")
        }
        ForEach(catalog, id: \.name) { label in
            Button {
                Haptics.selection()
                toggleLabel(label, on: workspace)
            } label: {
                HStack(spacing: 8) {
                    WorkspaceLabelDot(color: label.color)
                    Text(label.name)
                    Spacer(minLength: 12)
                    if isLabelAssigned(label, on: workspace) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Divider()
        Button("New label…", systemImage: "plus") {
            sheet = .newLabel(workspace)
        }
    }
}

// MARK: - Manage labels sheet

/// Rename, recolor (10-swatch palette), delete with confirmation. Assignments follow renames
/// on the daemon side; the catalog updates live via `workspace.label.update`.
struct LabelsManageSheet: View {
    let session: HostSession
    let onClose: () -> Void

    @State private var drafts: [String: String] = [:]
    @State private var deleting: WorkspaceLabelDefinition?
    @State private var deleteCount: Int?
    @State private var inlineError: String?


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            errorBar
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.panel)
        .confirmationDialog(
            "Delete \(deleting?.name ?? "label")?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete label", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleteMessage)
        }
        .task(id: deleting?.name) {
            deleteCount = nil
            guard let deleting else { return }
            deleteCount = await session.labels.inspectDelete(name: deleting.name)
        }
    }

    private var header: some View {
        ZStack {
            Text("Labels")
                .font(.paseo(.title, weight: .semibold))
            HStack {
                Button {
                    commitAllDrafts()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.glyph(.large, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder private var errorBar: some View {
        if let error = inlineError ?? session.labels.actionError {
            Text(error)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder private var content: some View {
        let catalog = session.labels.labels
        if catalog.isEmpty {
            Text("No labels yet. Create one from a workspace's Labels menu.")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("Rename, recolor or delete. Renaming follows every workspace carrying the label.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.captionInk)
                    .padding(.top, 10)
                ForEach(catalog, id: \.name) { label in
                    labelRow(label)
                }
            }
        }
    }

    private func labelRow(_ label: WorkspaceLabelDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                WorkspaceLabelDot(color: label.color, size: 12)
                TextField("Name", text: draftBinding(label.name))
                    .font(.paseo(.callout))
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit { commitRename(original: label.name) }
                Button {
                    deleteCount = nil
                    deleting = label
                } label: {
                    Image(systemName: "trash")
                        .font(.glyph(.regular, weight: .regular))
                        .foregroundStyle(Palette.failureInk)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(label.name)")
            }
            VStack(spacing: 4) {
                ForEach(Array(stride(from: 0, to: WorkspaceLabelColor.allKnown.count, by: 5)), id: \.self) { start in
                    HStack(spacing: 4) {
                        Spacer(minLength: 22)
                        ForEach(WorkspaceLabelColor.allKnown[start..<min(start + 5, WorkspaceLabelColor.allKnown.count)], id: \.rawValue) { candidate in
                            LabelColorSwatch(
                                color: candidate,
                                selected: labelKey(candidate) == labelKey(label.color)
                            ) {
                                recolor(label, to: candidate)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var deleteMessage: String {
        switch deleteCount {
        case .some(let count):
            return count == 1
                ? "It's carried by 1 workspace. This can't be undone."
                : "It's carried by \(count) workspaces. This can't be undone."
        case .none:
            return "Workspaces carrying it will stop showing it. This can't be undone."
        }
    }

    private func draftBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { drafts[name] ?? name },
            set: { drafts[name] = $0 })
    }

    /// Applies every pending rename. Called when the sheet closes.
    private func commitAllDrafts() {
        for (original, draft) in drafts where normalizedLabelName(draft) != original {
            commitRename(original: original, revertOnFailure: true)
        }
    }

    private func commitRename(original: String, revertOnFailure: Bool = false) {
        let candidate = normalizedLabelName(drafts[original] ?? original)
        guard !candidate.isEmpty, candidate != original else {
            if revertOnFailure { drafts[original] = original }
            return
        }
        Task {
            let ok = await session.labels.updateLabel(name: original, newName: candidate)
            if ok {
                var updated = drafts
                updated.removeValue(forKey: original)
                drafts = updated
            } else {
                inlineError = session.labels.actionError ?? "Couldn't rename the label."
                if revertOnFailure { drafts[original] = original }
            }
        }
    }

    private func recolor(_ label: WorkspaceLabelDefinition, to color: WorkspaceLabelColor) {
        guard labelKey(color) != labelKey(label.color) else { return }
        Haptics.selection()
        Task {
            let ok = await session.labels.updateLabel(name: label.name, color: color)
            if !ok {
                inlineError = session.labels.actionError ?? "Couldn't recolor the label."
            }
        }
    }

    private func confirmDelete() {
        guard let target = deleting else { return }
        deleting = nil
        Haptics.light()
        Task {
            let ok = await session.labels.deleteLabel(name: target.name)
            var updated = drafts
            updated.removeValue(forKey: target.name)
            drafts = updated
            if !ok {
                inlineError = session.labels.actionError ?? "Couldn't delete the label."
            }
        }
    }
}

// MARK: - New label sheet

/// Create a label and assign it to one workspace in a single `assignment.set` (an unknown name
/// mints the catalog entry). A name that matches an existing label assigns that one instead.
struct NewLabelSheet: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor
    let onClose: () -> Void

    @State private var name = ""
    @State private var color: WorkspaceLabelColor = .teal


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldHint
                    TextField("Label name", text: $name)
                        .font(.paseo(.callout))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(submit)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
                    colorRow
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if session.labels.isWorking {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Create")
                                    .font(.paseo(.callout, weight: .semibold))
                            }
                            Spacer()
                        }
                        .frame(height: 46)
                        .background(canCreate ? Palette.unread : Palette.chip, in: .rect(cornerRadius: Radius.md))
                        .foregroundStyle(canCreate ? Color.white : Palette.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    if let error = session.labels.actionError {
                        Text(error)
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.failureInk)
                    }
                    if matchesExisting {
                        Text("Matches an existing label — it will be assigned instead of duplicated.")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.captionInk)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.panel)
    }

    private var canCreate: Bool {
        !normalizedLabelName(name).isEmpty && !session.labels.isWorking
    }

    private var matchesExisting: Bool {
        let candidate = normalizedLabelName(name).lowercased()
        guard !candidate.isEmpty else { return false }
        return session.labels.labels.contains { $0.name.lowercased() == candidate }
    }

    private var fieldHint: some View {
        Text("Appears on the workspace row and in the sidebar label filter.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.top, 14)
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stride(from: 0, to: WorkspaceLabelColor.allKnown.count, by: 5)), id: \.self) { start in
                HStack(spacing: 2) {
                    ForEach(WorkspaceLabelColor.allKnown[start..<min(start + 5, WorkspaceLabelColor.allKnown.count)], id: \.rawValue) { candidate in
                        LabelColorSwatch(
                            color: candidate,
                            selected: labelKey(candidate) == labelKey(color)
                        ) {
                            color = candidate
                            Haptics.selection()
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("New label")
                .font(.paseo(.title, weight: .semibold))
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.glyph(.large, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func submit() {
        let trimmed = normalizedLabelName(name)
        guard !trimmed.isEmpty, !session.labels.isWorking else { return }
        Task {
            let ok = await session.labels.createAndAssign(
                name: trimmed, color: color, toWorkspace: workspace.id)
            if ok {
                Haptics.success()
                onClose()
            }
        }
    }
}
#endif
