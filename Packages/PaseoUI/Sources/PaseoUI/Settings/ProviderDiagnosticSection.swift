#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Provider detail: the daemon's diagnostic log for this provider, or its failure message.
struct ProviderDiagnosticSection: View {
    let diagnostic: HostSettingsStore.ProviderDiagnosticState?

    var body: some View {
        SettingsSectionLabel(title: "Diagnostic")
        RowGroup {
            switch diagnostic {
            case .loading, .none:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Palette.ink)
                    Text("Running diagnostic…")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 52)
            case .ready(let text):
                ProviderDiagnosticPane(text: text, isFailure: false)
            case .failed(let message):
                ProviderDiagnosticPane(text: message, isFailure: true)
            }
        }
    }
}
#endif
