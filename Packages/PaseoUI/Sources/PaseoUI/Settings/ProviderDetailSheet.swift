#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The provider detail sheet: status, the daemon's diagnostic log (mono, copyable), the
/// discovered models (read-only) and the config-owned custom models (add/remove).
/// Opened by tapping a provider on Settings → Providers.
struct ProviderDetailSheet: View {
    let session: HostSession
    let providerID: String

    @State private var newModelID = ""
    @State private var modelError: String?


    private var entry: ProviderSnapshotEntry? { session.agentControl.provider(providerID) }
    private var diagnostic: HostSettingsStore.ProviderDiagnosticState? {
        session.hostSettings.providerDiagnostics[providerID]
    }
    private var customModels: [DaemonProviderModel] {
        session.hostSettings.additionalModels(for: providerID)
    }
    private var discoveredModels: [AgentModelDefinition] {
        entry?.models ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                statusSection
                diagnosticSection
                discoveredSection
                customModelsSection
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
        .onAppear {
            if session.agentControl.phase == .idle {
                Task { await session.agentControl.loadCatalog() }
            }
        }
    }

    // MARK: Status

    @ViewBuilder private var statusSection: some View {
        sectionLabel("Status")
        RowGroup {
            HStack(spacing: 12) {
                PaseoStatusDot(kind: dotKind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.paseo(.body))
                    Text(statusDetail)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            RowDivider()
            statusRow(symbol: "shippingbox", title: "Source", detail: entry?.source ?? "builtin")
            RowDivider()
            statusRow(symbol: "clock", title: "Catalogue", detail: catalogueDetail)
            if let error = entry?.error, !error.isEmpty {
                RowDivider()
                InlineBanner(.failure, title: error)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, 10)
            }
        }
    }

    private func statusRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.paseo(.body))
                Text(detail)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var dotKind: PaseoStatusDot.Kind {
        if session.hostSettings.config != nil, !session.hostSettings.isProviderEnabled(providerID) {
            return .idle
        }
        guard let status = entry?.status else { return .idle }
        switch status {
        case .ready: return .done
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
        let models = "\(count) \(count == 1 ? "model" : "models")"
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
            return "Fetched \(Self.relative(date))"
        }
        return "Fetched \(fetched)"
    }

    // MARK: Diagnostic

    @ViewBuilder private var diagnosticSection: some View {
        sectionLabel("Diagnostic")
        RowGroup {
            switch diagnostic {
            case .loading, .none:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Palette.ink)
                    Text("Running diagnostic…")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            case .ready(let text):
                diagnosticPane(text, isFailure: false)
            case .failed(let message):
                diagnosticPane(message, isFailure: true)
            }
        }
    }

    private func diagnosticPane(_ text: String, isFailure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text.isEmpty ? "The daemon returned an empty diagnostic." : text)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(isFailure ? Palette.failureInk : Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 220)
            HStack {
                CopyButton(text: text, label: "Copy diagnostic")
                    .accessibilityIdentifier("settings.providers.diagnostic.copy")
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    // MARK: Discovered models

    @ViewBuilder private var discoveredSection: some View {
        sectionLabel("Discovered")
        RowGroup {
            if discoveredModels.isEmpty {
                Text(emptyDiscoveredText)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
            } else {
                ForEach(Array(discoveredModels.enumerated()), id: \.element.id) { index, model in
                    discoveredModelRow(model)
                    if index < discoveredModels.count - 1 { RowDivider() }
                }
            }
        }
        Text("Models the daemon probes for this provider. Read-only; the daemon owns the catalogue.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
    }

    private func discoveredModelRow(_ model: AgentModelDefinition) -> some View {
        let unavailable = model.isSelectable == false
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(model.label)
                        .font(.paseo(.body))
                        .foregroundStyle(unavailable ? Palette.secondaryInk : Palette.ink)
                        .lineLimit(1)
                    if model.isDefault == true {
                        Text("Default")
                            .font(.paseo(.caption2, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Palette.chip, in: .capsule)
                    }
                    if unavailable {
                        Text("Unavailable")
                            .font(.paseo(.caption2, weight: .semibold))
                            .foregroundStyle(Palette.failureInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Palette.chip, in: .capsule)
                    }
                }
                Text(model.id)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var emptyDiscoveredText: String {
        if session.agentControl.phase == .loading { return "Loading models…" }
        if case .failed(let message) = session.agentControl.phase { return message }
        return "No models discovered."
    }

    // MARK: Custom models

    @ViewBuilder private var customModelsSection: some View {
        sectionLabel("Custom")
        RowGroup {
            if customModels.isEmpty {
                Text("No custom models. Add one below.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
            } else {
                ForEach(Array(customModels.enumerated()), id: \.element.id) { index, model in
                    customModelRow(model)
                    if index < customModels.count - 1 { RowDivider() }
                }
            }
            RowDivider()
            addCustomModelRow
        }
        if let modelError {
            InlineBanner(.failure, title: modelError)
                .padding(.horizontal, Space.lg)
        }
        Text("Custom models live in the daemon's config, merged into this provider's catalogue.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
    }

    private func customModelRow(_ model: DaemonProviderModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.label)
                    .font(.paseo(.body))
                    .lineLimit(1)
                Text(model.id)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.selection()
                removeCustomModel(model)
            } label: {
                Image(systemName: "trash")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.failureInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(model.label)")
            .accessibilityIdentifier("settings.providers.custom.remove.\(model.id)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var addCustomModelRow: some View {
        HStack(spacing: 12) {
            TextField("Model ID", text: $newModelID)
                .font(.paseo(.code))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { addCustomModel() }
            Button("Add") {
                Haptics.selection()
                addCustomModel()
            }
            .font(.paseo(.callout, weight: .semibold))
            .foregroundStyle(newModelID.trimmingCharacters(in: .whitespaces).isEmpty
                ? Palette.secondaryInk : Palette.ink)
            .disabled(newModelID.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("settings.providers.custom.add")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: Add / remove custom models

    private func addCustomModel() {
        let trimmed = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            modelError = "Enter a model ID."
            return
        }
        if customModels.contains(where: { $0.id == trimmed })
            || discoveredModels.contains(where: { $0.id == trimmed }) {
            modelError = "A model with that ID already exists."
            return
        }
        modelError = nil
        newModelID = ""
        setCustomModels(customModels + [DaemonProviderModel(id: trimmed, label: trimmed)])
    }

    private func removeCustomModel(_ model: DaemonProviderModel) {
        modelError = nil
        setCustomModels(customModels.filter { $0.id != model.id })
    }

    /// Writes the whole `additionalModels` array for this provider (a per-provider merge, like
    /// the enable switch), then asks the daemon to re-probe so the catalogue picks it up.
    private func setCustomModels(_ next: [DaemonProviderModel]) {
        var patch = DaemonConfigPatch()
        patch.providers = [providerID: .init(additionalModels: next)]
        Task {
            let ok = await session.hostSettings.save(patch)
            if ok {
                await session.agentControl.refreshCatalog()
            } else {
                modelError = session.hostSettings.error ?? "The daemon rejected that change."
            }
        }
    }

    // MARK: Shared bits

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}
#endif
