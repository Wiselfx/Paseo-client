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
                    Haptics.selection()
                    appearance = choice.rawValue
                } label: {
                    VStack(spacing: 9) {
                        preview(choice)
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
    }

    @ViewBuilder private func preview(_ choice: ClaudeAppearance) -> some View {
        switch choice {
        case .light:
            ZStack {
                Palette.Swatch.light
                bars(dark: true)
            }
            .clipShape(.rect(cornerRadius: Radius.md))
            .frame(maxWidth: .infinity)
        case .dark:
            ZStack {
                Palette.Swatch.dark
                bars(dark: false)
            }
            .clipShape(.rect(cornerRadius: Radius.md))
            .frame(maxWidth: .infinity)
        case .system:
            ZStack {
                HStack(spacing: 0) {
                    Palette.Swatch.light
                    Palette.Swatch.dark
                }
                bars(dark: true)
            }
            .clipShape(.rect(cornerRadius: Radius.md))
            .frame(maxWidth: .infinity)
        case .pureBlack:
            ZStack {
                Palette.Swatch.pureBlack
                bars(dark: false)
            }
            .clipShape(.rect(cornerRadius: Radius.md))
            .frame(maxWidth: .infinity)
        }
    }

    private func bars(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.8 : 0.5))
                .frame(width: 40, height: 5)
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.4 : 0.3))
                .frame(width: 26, height: 5)
            Spacer(minLength: 0)
        }
        .padding(12)
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
