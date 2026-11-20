#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Name + command editor for one script.
struct ScriptEditSheet: View {
    @State var script: ProjectScriptDraft
    var onSave: (ProjectScriptDraft) -> Void
    var onCancel: () -> Void


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
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(
                            Palette.ink.opacity(canSave ? 1 : 0.35), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.top, 4)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }

    private func field(title: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            ZStack(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.paseo(.code))
                        .foregroundStyle(Palette.tertiaryInk)
                        .allowsHitTesting(false)
                }
                TextField("", text: text)
                    .font(.paseo(.code))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
        }
    }
}
#endif
