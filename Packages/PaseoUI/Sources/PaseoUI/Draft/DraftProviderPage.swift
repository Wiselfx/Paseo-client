#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The provider page of `DraftControlsSheet`: every enabled provider, in the daemon's order; one
/// that is still probing says so and fills in through `providers_snapshot_update`. Only a ready
/// one can be picked.
struct DraftProviderPage: View {
    let providers: [ProviderSnapshotEntry]
    let selectedId: String?
    let phase: AgentControlStore.CatalogPhase
    let onSelect: (ProviderSnapshotEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if providers.isEmpty {
                    emptyState
                } else {
                    RowGroup {
                        ForEach(providers.enumerated(), id: \.element.id) { index, provider in
                            ListRow(
                                title: provider.label ?? provider.provider,
                                subtitle: detail(provider),
                                accessory: accessory(provider)
                            ) {
                                guard provider.isAvailable else { return }
                                onSelect(provider)
                            }
                            if index < providers.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch phase {
        case .loading, .idle:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        case .failed(let message):
            Text(message)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        case .ready:
            Text("No enabled providers on this host.")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    private func detail(_ provider: ProviderSnapshotEntry) -> String? {
        switch provider.status {
        case .ready: provider.description
        case .loading: "Loading models…"
        case .error: provider.error ?? "This provider could not start."
        case .unavailable: provider.error ?? "Not available on this host."
        case .unknown(let raw): raw.isEmpty ? nil : raw
        }
    }

    private func badge(_ provider: ProviderSnapshotEntry) -> String? {
        switch provider.status {
        case .ready: nil
        case .loading: "Loading"
        case .error: "Error"
        case .unavailable: "Unavailable"
        case .unknown: nil
        }
    }

    /// Selected wins over the badge.
    private func accessory(_ provider: ProviderSnapshotEntry) -> ListRow.Accessory {
        if selectedId == provider.provider { return .checkmark(true) }
        if let badge = badge(provider) { return .badge(badge) }
        return .none
    }
}
#endif
