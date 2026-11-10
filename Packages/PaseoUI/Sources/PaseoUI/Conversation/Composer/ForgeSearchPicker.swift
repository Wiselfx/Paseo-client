#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// "Attach issue or PR": a searchable forge picker for the composer, upstream's combobox in
/// sheet form (`packages/app/src/composer/index.tsx` GitHub picker, wording from
/// `en.ts` `composer.github.*`). Debounced search through `ForgeSearchStore` (modern
/// `forge.search.request` or the legacy GitHub fallback), a kind filter, and the M3j forge
/// setup callout when the host can't answer. Picking toggles the attachment into the tray.
struct ForgeSearchPicker: View {
    let session: HostSession
    let cwd: String
    /// GitLab wording ("Attach issue or MR", "Search issues and MRs…") when the workspace's
    /// forge is GitLab; resolved from the checkout's PR status by the presenter.
    var isMergeRequest: Bool = false
    /// Called with the picked item; the presenter toggles it into the tray and dismisses.
    var onPick: (ForgeSearchItem) -> Void
    /// Items already in the tray, for the checkmark (upstream's selected state).
    var selectedIds: [String] = []
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var kindFilter: KindFilter = .all
    @State private var result: ForgeSearchResult?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    private let typography = ClaudeTypography()
    private var store: ForgeSearchStore { session.forgeSearch }

    enum KindFilter: String, CaseIterable {
        case all
        case issues
        case changeRequests

        var kinds: [ForgeSearchItem.Kind]? {
            switch self {
            case .all: nil
            case .issues: [.issue]
            case .changeRequests: [.changeRequest]
            }
        }
    }

    private var title: String { isMergeRequest ? "Attach issue or MR" : "Attach issue or PR" }
    private var placeholder: String {
        isMergeRequest ? "Search issues and MRs…" : "Search issues and PRs…"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title) { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                searchField
                kindFilterRow
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onDisappear { searchTask?.cancel() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
            TextField("", text: $query, prompt: Text(placeholder).foregroundStyle(ClaudePalette.secondaryInk))
                .font(typography.sans(17))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, value in scheduleSearch(value) }
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    scheduleSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(ClaudePalette.chip, in: .capsule)
    }

    private var kindFilterRow: some View {
        HStack(spacing: 6) {
            ForEach(KindFilter.allCases, id: \.self) { filter in
                Button {
                    Haptics.selection()
                    kindFilter = filter
                    scheduleSearch(query)
                } label: {
                    Text(filterLabel(filter))
                        .font(typography.sans(13, weight: kindFilter == filter ? .medium : .regular))
                        .foregroundStyle(
                            kindFilter == filter ? ClaudePalette.background : ClaudePalette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            kindFilter == filter ? ClaudePalette.ink : ClaudePalette.chip,
                            in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filterLabel(_ filter: KindFilter) -> String {
        switch filter {
        case .all: "All"
        case .issues: "Issues"
        case .changeRequests: isMergeRequest ? "MRs" : "PRs"
        }
    }

    @ViewBuilder private var content: some View {
        if let forgeCallout {
            authCallout(forgeCallout)
        }
        if let searchError {
            Text(searchError)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let result, let error = result.error, !error.isEmpty {
            Text(error)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let result {
            if result.items.isEmpty {
                if !isSearching {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Type to search."
                        : "No results found.")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            } else {
                ScrollView {
                    RowGroup {
                        ForEach(Array(result.items.enumerated()), id: \.element.id) { index, item in
                            resultRow(item)
                            if index < result.items.count - 1 { RowDivider() }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// The M3j forge setup callout, reused: same titles and host commands as the Changes page.
    private enum AuthCallout: Equatable {
        case cliMissing
        case unauthenticated

        var title: String {
            switch self {
            case .cliMissing: "GitHub CLI isn't installed on this host"
            case .unauthenticated: "GitHub CLI isn't authenticated on this host"
            }
        }

        var commands: [String] {
            switch self {
            case .cliMissing: ["brew install gh", "sudo apt install gh", "gh auth login"]
            case .unauthenticated: ["gh auth login"]
            }
        }
    }

    private var forgeCallout: AuthCallout? {
        switch result?.authState {
        case .cliMissing: .cliMissing
        case .unauthenticated: .unauthenticated
        default: nil
        }
    }

    private func authCallout(_ callout: AuthCallout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(callout.title)
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("Run this on the host, then refresh:")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.secondaryInk)
            ForEach(callout.commands, id: \.self) { command in
                Text(command)
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ClaudePalette.chip, in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ClaudePalette.warning.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func resultRow(_ item: ForgeSearchItem) -> some View {
        let selected = selectedIds.contains(item.id)
        return Button {
            Haptics.selection()
            onPick(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.kind == .changeRequest ? "arrow.triangle.branch" : "exclamationmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.resultTitle(item))
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    if !item.labels.isEmpty {
                        Text(item.labels.joined(separator: " · "))
                            .font(typography.sans(11))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                        .accessibilityLabel("Selected")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), select")
        .accessibilityValue(selected ? "Selected" : "")
    }

    private static func resultTitle(_ item: ForgeSearchItem) -> String {
        guard let number = item.number else { return item.title }
        return "#\(number) \(item.title)"
    }

    /// Debounced like the Add project search (300 ms); the store picks the transport.
    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                result = nil
                searchError = nil
                return
            }
            isSearching = true
            let found = await store.search(cwd: cwd, query: trimmed, kinds: kindFilter.kinds)
            guard !Task.isCancelled else { return }
            isSearching = false
            result = found
            searchError = store.error
        }
    }
}
#endif
