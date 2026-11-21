#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Upstream's `ResumePromptSheet`: the saved prompt (or the default), Cancel and Save. Save
/// needs a change and a non-blank prompt. The draft, saving and focus state live here, so a
/// keystroke re-evaluates the sheet and not the Agents page behind it.
struct ResumePromptSheet: View {
    let hostSettings: HostSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        SheetScaffold("Resume prompt", detents: .medium) {
            VStack(alignment: .leading, spacing: Space.lg) {
                TextField("Resume working.", text: binding, axis: .vertical)
                    .font(.paseo(.codeSmall))
                    .lineLimit(4...12)
                    .padding(Space.md)
                    .background(Palette.background.opacity(0.55), in: .rect(cornerRadius: Radius.md))
                    .focused($focused)
                    .accessibilityLabel("Resume prompt")
                if let error = hostSettings.error {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                }
                HStack(spacing: Space.md) {
                    Button("Cancel") { close() }
                        .buttonStyle(.paseoSecondary)
                        .disabled(saving)
                    Spacer(minLength: 0)
                    Button(saving ? "Saving…" : "Save") { save() }
                        .buttonStyle(.paseoPrimary(isWorking: saving))
                        .disabled(!canSave)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.md)
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { draft ?? hostSettings.config?.resumePrompt ?? "" },
            set: { draft = $0 })
    }

    private var isDirty: Bool {
        guard let draft else { return false }
        return draft != (hostSettings.config?.resumePrompt ?? "")
    }

    private func save() {
        guard let draft else { return }
        saving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.resumePrompt = draft
            let ok = await hostSettings.save(patch)
            saving = false
            if ok {
                self.draft = nil
                Haptics.success()
            }
            focused = false
            if ok { dismiss() }
        }
    }

    private func close() {
        draft = nil
        focused = false
        dismiss()
    }

    private var canSave: Bool {
        guard let draft, isDirty, !saving else {
            return false
        }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
#endif
