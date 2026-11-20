#if canImport(UIKit)
import SwiftUI

/// The pre-connect Settings entry: appearance and text sizes, using the same keys as the
/// general settings page. The full Settings screen needs a host (it is host-scoped).
struct WelcomeAppearanceSheet: View {
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Appearance", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppearancePicker(identifierPrefix: "welcome.appearance")
                    scaleRow("Content size", options: ClaudeTextScale.Content.allCases,
                             current: contentTextSize) { contentTextSize = $0.rawValue }
                    scaleRow("Code size", options: ClaudeTextScale.Code.allCases,
                             current: codeFontSize) { codeFontSize = $0.rawValue }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }


    private func scaleRow<Option: CaseIterable & RawRepresentable & Equatable>(
        _ title: String, options: [Option], current: String,
        onSelect: @escaping (Option) -> Void
    ) -> some View where Option.RawValue == String {
        HStack {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: 8)
            Menu {
                ForEach(Array(options), id: \.rawValue) { option in
                    Button {
                        Haptics.selection()
                        onSelect(option)
                    } label: {
                        Label(
                            option.rawValue,
                            systemImage: current == option.rawValue ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(current)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
    }
}
#endif
