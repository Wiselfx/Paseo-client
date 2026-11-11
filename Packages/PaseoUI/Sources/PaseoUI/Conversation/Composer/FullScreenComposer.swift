#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8b: draft metrics and the full-height editor sheet for long drafts.
enum DraftMetrics {
    /// Rough per-line budget for the composer at 18 pt on a phone in portrait.
    static let charsPerLine = 34

    /// Effective line count (explicit newlines, plus wrapping at ~`charsPerLine` per line).
    ///
    /// One grapheme pass, no array: this runs on every change of the draft, so `split` (which
    /// allocates one `Substring` per line) would allocate per keystroke on a long paste. The
    /// arithmetic is the same: each line, terminated by `\n` or by the end of the text, is
    /// `max(1, ceil(characters / charsPerLine))` lines, and an empty draft is 0 lines.
    ///
    /// The expand control's threshold and its hysteresis are **not** here: they are sticky between
    /// `ComposerMetrics.expandShowLines` and `expandHideLines`, because a single threshold turns a
    /// word wrapping at the boundary into the control (and its field reserve) flickering on
    /// consecutive keystrokes (H3 §2).
    static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var lines = 0
        var charactersInLine = 0
        for character in text {
            if character == "\n" {
                lines += wrappedLines(charactersInLine)
                charactersInLine = 0
            } else {
                charactersInLine += 1
            }
        }
        return lines + wrappedLines(charactersInLine)
    }

    private static func wrappedLines(_ characters: Int) -> Int {
        max(1, Int((Double(characters) / Double(charsPerLine)).rounded(.up)))
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


    private var trimmedEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Done") { dismiss() }
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Done")
                Spacer()
                Text("Message")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Send") {
                    onSend()
                    dismiss()
                }
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(trimmedEmpty ? Palette.secondaryInk : Palette.accentInk)
                .disabled(trimmedEmpty)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .accessibilityLabel(isRunning ? "Send and steer" : "Send message")
                .accessibilityIdentifier("composer.fullscreen.send")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            ClaudeDivider()
            TextEditor(text: $draft)
                .font(.paseo(.body))
                .foregroundStyle(Palette.ink)
                .tint(Palette.accentInk)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .focused($focused)
                .accessibilityIdentifier("composer.fullscreen.editor")
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .onAppear { focused = true }
    }
}
#endif
