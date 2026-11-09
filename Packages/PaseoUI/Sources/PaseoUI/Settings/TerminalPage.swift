#if canImport(UIKit)
import SwiftUI

/// Settings → Terminal: how much scrollback SwiftTerm keeps. Read live by `PaseoTerminalView`.
struct TerminalPage: View {
    /// Shared with `Workspace/PaseoTerminalView.swift`. Default 2,000 lines.
    @AppStorage("paseo.terminal.scrollback") private var scrollback = 2_000

    private let typography = ClaudeTypography()
    private let options: [(label: String, value: Int)] = [
        ("1,000 lines", 1_000),
        ("2,000 lines", 2_000),
        ("5,000 lines", 5_000),
        ("10,000 lines", 10_000),
    ]

    private var selectedLabel: String {
        options.first { $0.value == scrollback }?.label ?? "2,000 lines"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Terminal")
                RowGroup {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scrollback")
                                .font(.system(size: 17))
                            Text("Lines kept in the buffer")
                                .font(.system(size: 13))
                                .foregroundStyle(ClaudePalette.secondary)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(options, id: \.value) { option in
                                Button {
                                    Haptics.selection()
                                    scrollback = option.value
                                } label: {
                                    Label(
                                        option.label,
                                        systemImage: scrollback == option.value
                                            ? "checkmark" : "circle")
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(selectedLabel)
                                    .font(.system(size: 15))
                                    .foregroundStyle(ClaudePalette.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                        }
                        .accessibilityLabel("Terminal scrollback, currently \(selectedLabel)")
                        .accessibilityIdentifier("settings.terminal.scrollback")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                Text("Applies to new and already-open terminal views on this device.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
