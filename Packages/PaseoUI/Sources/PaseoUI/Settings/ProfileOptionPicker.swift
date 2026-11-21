#if canImport(UIKit)
import SwiftUI

/// One option row of the profile editor: the title, and the current value as a menu button.
/// The menu holds an inline `Picker`, so the system marks the selected option and VoiceOver
/// announces it. Callers tag each option with the value it selects.
struct ProfileOptionPicker<Value: Hashable, Options: View>: View {
    let title: String
    let current: String
    @Binding var selection: Value
    private let options: Options

    init(
        title: String,
        current: String,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.current = current
        self._selection = selection
        self.options = options()
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: Space.sm)
            Menu {
                Picker(title, selection: $selection) {
                    options
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(current)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
    }
}
#endif
