#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8b: draft metrics and the full-height editor sheet for long drafts.
enum DraftMetrics {
    /// Rough per-line budget for the composer at 18 pt on a phone in portrait.
    static let charsPerLine = 34
    /// Shows the expand control when the draft occupies at least this many effective lines.
    static let tallLineThreshold = 5

    /// Effective line count (explicit newlines, plus wrapping at ~`charsPerLine` per line).
    static func lineCount(_ text: String) -> Int {
        var lines = 0
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for rawLine in rawLines {
            lines += max(1, Int((Double(rawLine.count) / Double(charsPerLine)).rounded(.up)))
        }
        return lines
    }

    static func isTall(_ text: String) -> Bool {
        lineCount(text) >= tallLineThreshold
    }
}

/// The full-height draft editor for long drafts. Shares the composer's draft binding; same
/// Sans as the composer at 17 pt. Done keeps the draft; Send sends it.
struct FullScreenComposer: View {
    @Binding var draft: String
    let isRunning: Bool
    let onSend: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private let typography = ClaudeTypography()

    private var trimmedEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Done") { dismiss() }
                    .font(typography.sans(16))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Done")
                Spacer()
                Text("Message")
                    .font(typography.sans(16, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer()
                Button("Send") {
                    onSend()
                    dismiss()
                }
                .font(typography.sans(16, weight: .semibold))
                .foregroundStyle(trimmedEmpty ? ClaudePalette.secondaryInk : ClaudePalette.orange)
                .disabled(trimmedEmpty)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityLabel(isRunning ? "Send and steer" : "Send message")
                .accessibilityIdentifier("composer.fullscreen.send")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            ClaudeDivider()
            TextEditor(text: $draft)
                .font(typography.sans(17))
                .foregroundStyle(ClaudePalette.ink)
                .tint(ClaudePalette.orange)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .focused($focused)
                .accessibilityIdentifier("composer.fullscreen.editor")
        }
        .background(ClaudePalette.background.ignoresSafeArea())
        .foregroundStyle(ClaudePalette.ink)
        .onAppear { focused = true }
    }
}
#endif
