#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

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
        // Pending renames are committed on every way out, including a swipe-down, which the
        // scaffold's close button does not see.
        SheetScaffold("Labels", detents: .large, onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                errorBar
                ScrollView {
                    content
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .confirmationDialog(
                "Delete \(deleting?.name ?? "label")?",
                item: $deleting,
                titleVisibility: .visible
            ) { label in
                Button("Delete label", role: .destructive) { confirmDelete(label) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(deleteMessage)
            }
            .task(id: deleting?.name) {
                deleteCount = nil
                guard let deleting else { return }
                deleteCount = await session.labels.inspectDelete(name: deleting.name)
            }
        }
        .onDisappear { commitAllDrafts() }
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

    /// A row's field: its pending rename, or the label's own name until one is typed. (A key path
    /// can't carry `subscript(_:default:)`, whose default is an autoclosure.)
    private func draftBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { drafts[name] ?? name },
            set: { drafts[name] = $0 })
    }

    /// Applies every pending rename. Called once, when the sheet disappears.
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

    private func confirmDelete(_ target: WorkspaceLabelDefinition) {
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
#endif
