#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Name + command editor for one script.
struct ScriptEditSheet: View {
    @State private var script: ProjectScriptDraft
    var onSave: (ProjectScriptDraft) -> Void
    var onCancel: () -> Void

    init(
        script: ProjectScriptDraft,
        onSave: @escaping (ProjectScriptDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _script = State(initialValue: script)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var canSave: Bool {
        !script.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: script.command.isEmpty && script.name.isEmpty ? "New script" : "Script", close: onCancel)
            VStack(alignment: .leading, spacing: 18) {
                field(title: "Name", text: $script.name, placeholder: "start-ios", mono: true)
                field(title: "Command", text: $script.command, placeholder: "npm run dev", mono: true)
                Button {
                    guard canSave else { return }
                    var saved = script
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                    onSave(saved)
                    Haptics.light()
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.paseoPrimary())
                .disabled(!canSave)
                .padding(.top, Space.xs)
                Spacer()
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }

    private func field(title: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            TextField(
                title, text: text,
                prompt: Text(placeholder).foregroundStyle(Palette.tertiaryInk)
            )
            .font(.paseo(.code))
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, Space.md)
            .frame(minHeight: 48)
            .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
        }
    }
}
#endif
