#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

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
                        }
                    }
                }
            }
        }
        .paseoFeedback(.selection, trigger: color)
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
