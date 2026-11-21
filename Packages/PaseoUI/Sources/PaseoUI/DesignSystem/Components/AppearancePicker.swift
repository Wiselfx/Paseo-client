#if canImport(UIKit)
import SwiftUI

/// The appearance ladder (Light / Dark / Pure black / System): four preview tiles, the current one
/// ringed in `Palette.selection`. Shared by Settings and the welcome appearance sheet.
struct AppearancePicker: View {
    private let identifierPrefix: String

    @AppStorage(ClaudeAppearance.storageKey) private var appearance = ClaudeAppearance.system.rawValue

    init(identifierPrefix: String = "settings.appearance") {
        self.identifierPrefix = identifierPrefix
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach([ClaudeAppearance.light, .dark, .pureBlack, .system], id: \.self) { choice in
                Button {
                    select(choice)
                } label: {
                    VStack(spacing: 9) {
                        AppearanceSwatch(choice: choice)
                            .clipShape(.rect(cornerRadius: Radius.md))
                            .frame(maxWidth: .infinity)
                            .frame(height: 68)
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md).stroke(
                                    appearance == choice.rawValue ? Palette.selection : .clear,
                                    lineWidth: 2)
                            }
                        Text(choice.rawValue)
                            .font(.paseo(.callout))
                            .foregroundStyle(
                                appearance == choice.rawValue ? Palette.selection : Palette.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.rawValue) appearance")
                .accessibilityAddTraits(appearance == choice.rawValue ? .isSelected : [])
                .accessibilityIdentifier(identifierPrefix + "." + choice.rawValue)
            }
        }
        .paseoFeedback(.selection, trigger: appearance)
    }

    private func select(_ choice: ClaudeAppearance) {
        appearance = choice.rawValue
    }
}

#Preview("Light") {
    AppearancePicker()
        .padding()
        .background(Palette.background)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppearancePicker(identifierPrefix: "welcome.appearance")
        .padding()
        .background(Palette.background)
        .preferredColorScheme(.dark)
}
#endif
