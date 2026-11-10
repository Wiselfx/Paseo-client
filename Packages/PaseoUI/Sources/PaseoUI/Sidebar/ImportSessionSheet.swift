#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Import session: bring an existing CLI/terminal agent session from the host into a Paseo
/// agent, as upstream's import sheet does (`packages/app/src/components/import-session-sheet.tsx`,
/// wording from `en.ts` `importSession.*`). Scoped to one workspace ("This workspace") or the
/// whole host ("Show all"); per-provider listing with provider error rows; search debounced
/// 200 ms and only sent when `features.importSessionSearch`; the workspace target only when
/// `features.importSessionWorkspaceTarget`. Hidden by callers when the daemon lacks
/// `features.providersSnapshot` (the "Update the host…" state).
struct ImportSessionSheet: View {
    let session: HostSession
    /// The directory the sheet was opened for; nil opens host-wide.
    var cwd: String? = nil
    var workspaceId: String? = nil
    /// Called with the imported agent's id after a successful import.
    var onImported: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var debouncedQuery = ""
    @State private var showAll = false
    @State private var pageLimit = ImportSessionStore.pageLimits[0]
    @State private var selectedProvider = "__all__"
    @State private var searchTask: Task<Void, Never>?

    private var store: ImportSessionStore { session.importSession }
    private var scopeCwd: String? { showAll ? nil : cwd }

    /// Enabled providers, in the catalogue's order — the list the sheet fetches per provider.
    private var providersToFetch: [String] {
        session.agentControl.providers.filter(\.enabled).map(\.provider)
    }

    private var visibleEntries: [RecentProviderSessionDescriptor] {
        guard selectedProvider != "__all__" else { return store.entries }
        return store.entries.filter { $0.providerId == selectedProvider }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Import session") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scopeRow
                    if store.supportsSearch { searchField }
                    if providersToFetch.count > 1 { providerFilter }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await session.agentControl.loadCatalog(cwd: scopeCwd)
            await reload()
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func reload() async {
        await store.load(
            providers: providersToFetch, cwd: scopeCwd, query: debouncedQuery, limit: pageLimit)
    }

    // MARK: Scope + search

    private var scopeRow: some View {
        HStack(spacing: 8) {
            Text(scopeCwd == nil ? "Sessions on this host" : "This workspace")
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 0)
            if scopeCwd != nil {
                Button {
                    Haptics.selection()
                    showAll = true
                    pageLimit = ImportSessionStore.pageLimits[0]
                    Task { await reload() }
                } label: {
                    Text("Show all")
                        .font(.paseo(.footnote, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("importSession.showAll")
            }
        }
        .padding(.top, 2)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
            TextField("", text: $search, prompt: Text("Search sessions…").foregroundStyle(Palette.tertiaryInk))
                .font(.paseo(.body))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: search) { _, query in scheduleSearch(query) }
            if !search.isEmpty {
                Button {
                    search = ""
                    debouncedQuery = ""
                    pageLimit = ImportSessionStore.pageLimits[0]
                    Task { await reload() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Palette.chip, in: .capsule)
    }

    /// Debounced 200 ms, upstream's `SEARCH_DEBOUNCE_MS`: a typed word is one request.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            debouncedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            pageLimit = ImportSessionStore.pageLimits[0]
            await reload()
        }
    }

    private var providerFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                filterChip(id: "__all__", label: "All")
                ForEach(providersToFetch, id: \.self) { provider in
                    filterChip(
                        id: provider,
                        label: session.agentControl.provider(provider)?.label ?? provider)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(id: String, label: String) -> some View {
        Button {
            Haptics.selection()
            selectedProvider = id
        } label: {
            Text(label)
                .font(.paseo(.footnote, weight: selectedProvider == id ? .medium : .regular))
                .foregroundStyle(
                    selectedProvider == id ? Palette.background : Palette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(
                    selectedProvider == id ? Palette.ink : Palette.chip, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !store.supportsSnapshot {
            quietText("Update the host to import sessions.")
        } else if store.phase == .loading, store.entries.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading recent sessions…")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if providersToFetch.isEmpty, store.phase == .ready {
            quietText("No importable providers are enabled.")
        } else if case .failed = store.phase, store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.providerErrors.first?.message ?? "Could not load sessions.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                refreshButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
        } else {
            if !store.providerErrors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.providerErrors, id: \.provider) { error in
                        Text("Could not load \(providerLabel(error.provider)) sessions")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.failureInk)
                    }
                    refreshButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if visibleEntries.isEmpty {
                quietText(emptyText)
            } else {
                RowGroup {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        sessionRow(entry)
                        if index < visibleEntries.count - 1 { RowDivider() }
                    }
                }
                if store.hasMore {
                    Button {
                        pageLimit = ImportSessionStore.nextPageLimit(pageLimit)
                        Task { await reload() }
                    } label: {
                        Text("Load more")
                            .font(.paseo(.callout, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("importSession.loadMore")
                }
            }
            if let error = store.actionError {
                Text(error)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyText: String {
        if !debouncedQuery.isEmpty { return "No sessions match your search." }
        if selectedProvider != "__all__" {
            return "No \(providerLabel(selectedProvider)) sessions found."
        }
        if store.alreadyImportedCount > 0 { return "All recent sessions are already imported." }
        return "No recent sessions to import."
    }

    private func quietText(_ text: String) -> some View {
        Text(text)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    private var refreshButton: some View {
        Button {
            Haptics.selection()
            Task { await reload() }
        } label: {
            Label("Refresh sessions", systemImage: "arrow.clockwise")
                .font(.paseo(.footnote, weight: .medium))
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("importSession.refresh")
    }

    private func providerLabel(_ provider: String) -> String {
        session.agentControl.provider(provider)?.label ?? provider
    }

    private func sessionRow(_ entry: RecentProviderSessionDescriptor) -> some View {
        let importing = store.importingId == entry.id
        return Button {
            Haptics.selection()
            Task { await importEntry(entry) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayTitle)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(WorkspaceFileFormat.relativeModified(entry.lastActivityAt))
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                Text(entry.promptPreview)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if importing {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                    } else {
                        Text(providerLabel(entry.providerId))
                        if scopeCwd == nil {
                            Text("· \(entry.cwd)")
                        }
                    }
                }
                .font(.paseo(.caption2))
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.importingId != nil)
        .accessibilityIdentifier("importSession.row")
    }

    private func importEntry(_ entry: RecentProviderSessionDescriptor) async {
        let target = ImportSessionStore.importTargetWorkspaceId(
            entryCwd: entry.cwd, workspaceCwd: cwd, workspaceId: workspaceId,
            isScopedListing: scopeCwd != nil, supportsWorkspaceTarget: store.supportsWorkspaceTarget)
        guard
            let agent = await store.importSession(entry, cwd: entry.cwd, workspaceId: target)
        else { return }
        // The imported agent may live in another workspace; refresh so the shell can open it.
        await session.refreshAgents()
        dismiss()
        onImported(agent.id)
    }
}
#endif
