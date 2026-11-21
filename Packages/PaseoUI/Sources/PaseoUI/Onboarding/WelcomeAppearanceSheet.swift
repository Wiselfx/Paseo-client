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
                             selection: $contentTextSize)
                    scaleRow("Code size", options: ClaudeTextScale.Code.allCases,
                             selection: $codeFontSize)
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


    /// A `Picker` rather than a hand-built menu: VoiceOver gets the row's title and the selected size.
    private func scaleRow<Option: CaseIterable & RawRepresentable & Equatable>(
        _ title: String, options: [Option], selection: Binding<String>
    ) -> some View where Option.RawValue == String {
        HStack {
            Text(title)
                .font(.paseo(.body))
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                ForEach(Array(options), id: \.rawValue) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Palette.secondaryInk)
            .paseoFeedback(.selection, trigger: selection.wrappedValue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Space.sm)
        .frame(minHeight: 52)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
    }
}
#endif
