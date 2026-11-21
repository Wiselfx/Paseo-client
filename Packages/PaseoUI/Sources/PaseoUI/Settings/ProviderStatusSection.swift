#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Provider detail: the status dot and line, where the provider comes from and when its catalogue
/// was last fetched.
struct ProviderStatusSection: View {
    let session: HostSession
    let providerID: String

    private var entry: ProviderSnapshotEntry? { session.agentControl.provider(providerID) }
    private var discoveredModels: [AgentModelDefinition] { entry?.models ?? [] }

    var body: some View {
        SettingsSectionLabel(title: "Status")
        RowGroup {
            HStack(spacing: Space.md) {
                StatusDot(dotKind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.paseo(.body))
                    Text(statusDetail)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 52)
            RowDivider()
            ProviderStatusRow(symbol: "shippingbox", title: "Source", detail: entry?.source ?? "builtin")
            RowDivider()
            ProviderStatusRow(symbol: "clock", title: "Catalogue", detail: catalogueDetail)
            if let error = entry?.error, !error.isEmpty {
                RowDivider()
                InlineBanner(.failure, title: error)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, 10)
            }
        }
    }

    private var dotKind: StatusDot.State {
        if session.hostSettings.config != nil, !session.hostSettings.isProviderEnabled(providerID) {
            return .idle
        }
        guard let status = entry?.status else { return .idle }
        switch status {
        case .ready: return .idle
        case .loading: return .running
        case .error: return .failed
        case .unavailable: return .idle
        case .unknown: return .idle
        }
    }

    private var statusTitle: String {
        if session.hostSettings.config != nil, !session.hostSettings.isProviderEnabled(providerID) {
            return "Disabled"
        }
        guard let entry else { return "Loading…" }
        switch entry.status {
        case .ready: return "Ready"
        case .loading: return "Loading…"
        case .error: return "Error"
        case .unavailable: return "Not installed"
        case .unknown(let raw): return raw.isEmpty ? "Unknown" : raw
        }
    }

    private var statusDetail: String {
        let count = discoveredModels.count
        let models = String(
            AttributedString(localized: "^[\(count) model](inflect: true)", bundle: #bundle).characters)
        if session.hostSettings.config != nil, !session.hostSettings.isProviderEnabled(providerID) {
            return "Disabled · \(models)"
        }
        switch entry?.status {
        case .ready, .none:
            return models
        case .loading:
            return "Probing this provider · \(models) so far"
        case .error:
            return "Probe failed · \(models)"
        case .unavailable:
            return "The host cannot run this provider"
        case .unknown(let raw):
            return raw.isEmpty ? models : "\(raw) · \(models)"
        }
    }

    private var catalogueDetail: String {
        guard let fetched = entry?.fetchedAt else { return "Not fetched yet" }
        if let date = PaseoDate.parse(fetched) {
            return "Fetched \(PaseoFormat.relative(date))"
        }
        return "Fetched \(fetched)"
    }
}
#endif
