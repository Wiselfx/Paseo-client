#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Providers: the host's provider catalogue. A row pushes that provider's
/// detail page; its switch stores the enable flag in the host config (UX-SPEC §5: system-blue
/// toggles).
struct ProvidersPage: View {
    let session: HostSession

    private var catalog: AgentControlStore { session.agentControl }
    private var hostSettings: HostSettingsStore { session.hostSettings }

    var body: some View {
        PageList {
            if let actionError = catalog.actionError {
                Section {
                    InlineBanner(
                        .failure, title: actionError,
                        action: ("Try again", { Task { await catalog.refreshCatalog() } }))
                        .panelRow(Palette.background)
                }
            }
            if catalog.providers.isEmpty {
                Section {
                    stateRow
                        .panelRow(Palette.background)
                }
            } else {
                Section {
                    ForEach(catalog.providers) { provider in
                        providerRow(provider)
                    }
                } footer: {
                    Text(
                        "Enable switches are stored in the host's config; status and models come from its catalogue."
                    )
                }
            }
            if hostSettings.config == nil {
                Section {
                    InlineBanner(
                        .info,
                        title:
                            "Host config is unavailable — pull to refresh on a Host page to enable toggles."
                    )
                    .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Providers")
        .refreshable { await catalog.refreshCatalog() }
        .task {
            if catalog.phase == .idle { await catalog.loadCatalog() }
        }
    }

    /// Loading, failure and empty states, in one full-width row.
    @ViewBuilder private var stateRow: some View {
        if catalog.phase == .loading {
            LoadingState("Loading providers…")
                .frame(height: 120)
        } else if case .failed(let message) = catalog.phase {
            InlineBanner(.failure, title: message)
                .padding(Space.lg)
        } else {
            EmptyState(
                title: "No providers reported by this host",
                message: "Providers come from the host's catalogue."
            )
            .frame(minHeight: 160)
        }
    }

    /// The row pushes the provider; the switch is a sibling so a tap on it flips the flag
    /// instead of pushing (a control inside a NavigationLink label does not get its taps).
    private func providerRow(_ provider: ProviderSnapshotEntry) -> some View {
        HStack(spacing: 0) {
            NavigationLink(value: SettingsRoute.provider(provider.provider)) {
                HStack(spacing: Space.md) {
                    PaseoStatusDot(kind: dotKind(provider))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.label ?? provider.provider)
                            .font(.paseo(.body))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(detailLine(provider))
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.sm)
                }
                .padding(.leading, Space.lg)
                .padding(.vertical, Space.md)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.providers.open.\(provider.provider)")
            if hostSettings.config != nil {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { hostSettings.isProviderEnabled(provider.provider) },
                        set: { newValue in
                            save { patch in
                                patch.providers = [provider.provider: .init(enabled: newValue)]
                            }
                        })
                )
                .labelsHidden()
                .tint(Palette.toggleTint)
                .disabled(hostSettings.isSaving)
                .padding(.trailing, Space.lg)
                .accessibilityLabel("Enable \(provider.label ?? provider.provider)")
            }
        }
        .panelRow()
    }

    private func save(_ build: (inout DaemonConfigPatch) -> Void) {
        var patch = DaemonConfigPatch()
        build(&patch)
        Haptics.selection()
        Task { await hostSettings.save(patch) }
    }

    private func detailLine(_ provider: ProviderSnapshotEntry) -> String {
        let modelCount = provider.models?.count ?? 0
        let countLine = "\(modelCount) \(modelCount == 1 ? "model" : "models")"
        if hostSettings.config != nil, !hostSettings.isProviderEnabled(provider.provider) {
            return "\(countLine) · Disabled"
        }
        switch provider.status {
        case .ready: return "\(countLine) · Ready"
        case .loading: return "\(countLine) · Loading"
        case .error: return "\(countLine) · Error"
        case .unavailable: return "\(countLine) · Not available"
        case .unknown(let raw): return raw.isEmpty ? countLine : "\(countLine) · \(raw)"
        }
    }

    private func statusKind(_ status: ProviderStatus) -> PaseoStatusDot.Kind {
        switch status {
        case .ready: .done
        case .loading: .running
        case .error: .failed
        case .unavailable: .idle
        case .unknown: .idle
        }
    }

    /// Hollow dot when the provider is config-disabled; otherwise its catalogue status.
    private func dotKind(_ provider: ProviderSnapshotEntry) -> PaseoStatusDot.Kind {
        if hostSettings.config != nil, !hostSettings.isProviderEnabled(provider.provider) {
            return .idle
        }
        return statusKind(provider.status)
    }
}

/// One provider's detail page, pushed under Providers. The page itself is `ProviderDetailSheet`.
struct ProviderPage: View {
    let session: HostSession
    let providerID: String

    var body: some View {
        ProviderDetailSheet(session: session, providerID: providerID)
    }
}
#endif
