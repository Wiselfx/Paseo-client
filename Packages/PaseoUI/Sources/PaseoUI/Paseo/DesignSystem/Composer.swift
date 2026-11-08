import SwiftUI

/// The message field. Grows with its text; the trailing button sends, or stops a running agent
/// when the field is empty.
public struct Composer: View {
    @Binding var text: String
    var isRunning: Bool
    var placeholder: String
    var onSend: (String) -> Void
    var onStop: () -> Void
    @FocusState private var focused: Bool

    public init(text: Binding<String>, isRunning: Bool, placeholder: String = "Message", onSend: @escaping (String) -> Void, onStop: @escaping () -> Void) {
        _text = text
        self.isRunning = isRunning
        self.placeholder = placeholder
        self.onSend = onSend
        self.onStop = onStop
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsStop: Bool { isRunning && trimmed.isEmpty }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(1...8)
                .focused($focused)
                .padding(.vertical, 10)
                .padding(.leading, 16)
            Button(action: primaryAction) {
                Image(systemName: showsStop ? "stop.fill" : "arrow.up")
                    .font(.system(size: showsStop ? 13 : 16, weight: .bold))
                    .foregroundStyle(buttonEnabled ? Color.white : Palette.tertiaryInk)
                    .frame(width: 34, height: 34)
                    .background(buttonEnabled ? Palette.accent : Palette.surfaceRaised, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!buttonEnabled)
            .padding(.trailing, 6)
            .padding(.bottom, 5)
            .accessibilityLabel(showsStop ? "Stop" : "Send")
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.snappy(duration: 0.2), value: showsStop)
        .onChange(of: focused) { _, isFocused in if isFocused { Haptics.prepare() } }
    }

    private var buttonEnabled: Bool { showsStop || !trimmed.isEmpty }

    private func primaryAction() {
        if showsStop {
            Haptics.selection()
            onStop()
        } else {
            Haptics.send()
            onSend(trimmed)
        }
    }
}
