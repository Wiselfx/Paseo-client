#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The provider detail sheet: status, the daemon's diagnostic log (mono, copyable), the
/// discovered models (read-only) and the config-owned custom models (add/remove).
/// Opened by tapping a provider on Settings → Providers.
struct ProviderDetailSheet: View {
    let session: HostSession
    let providerID: String

    private var entry: ProviderSnapshotEntry? { session.agentControl.provider(providerID) }
    private var diagnostic: HostSettingsStore.ProviderDiagnosticState? {
        session.hostSettings.providerDiagnostics[providerID]
    }
    private var discoveredModels: [AgentModelDefinition] {
        entry?.models ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                ProviderStatusSection(session: session, providerID: providerID)
                ProviderDiagnosticSection(diagnostic: diagnostic)
                DiscoveredModelsSection(models: discoveredModels, emptyText: emptyDiscoveredText)
                CustomModelsSection(session: session, providerID: providerID)
            }
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await session.agentControl.refreshCatalog()
            _ = await session.hostSettings.providerDiagnostic(providerID)
        }
        .navigationTitle(entry?.label ?? providerID)
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.background)
        .task {
            if diagnostic == nil {
                _ = await session.hostSettings.providerDiagnostic(providerID)
            }
        }
        .task {
            if session.agentControl.phase == .idle {
                await session.agentControl.loadCatalog()
            }
        }
    }

    private var emptyDiscoveredText: String {
        if session.agentControl.phase == .loading { return "Loading models…" }
        if case .failed(let message) = session.agentControl.phase { return message }
        return "No models discovered."
    }
}
#endif
