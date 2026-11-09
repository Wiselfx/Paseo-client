#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M20: the deep-link host chooser, upstream `hosts/host-chooser.tsx`. Searchable, local-first
/// order, "No matching hosts" empty state (upstream strings, hardcoded there exactly as here:
/// title `Choose host` at `:85`, placeholder `Search hosts...` at `:248`, empty state at `:263`).
/// Rows show the label and the daemon identity, as upstream's `HostChooserRow` does (`:95-137`).
public struct HostChooserSheet: View {
    private let hosts: [DeepLinkHost]
    private let onChoose: (DeepLinkHost) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    private let typography = ClaudeTypography()

    public init(hosts: [DeepLinkHost], onChoose: @escaping (DeepLinkHost) -> Void) {
        // The caller decides when to ask; this view keeps upstream's local-first order.
        self.hosts = DeepLinkHost.localFirst(hosts)
        self.onChoose = onChoose
    }

    private var options: [DeepLinkHost] {
        hosts.filter { DeepLinkHost.matches($0, query: query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Choose host") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                searchField
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if options.isEmpty {
                            Text("No matching hosts")
                                .font(typography.sans(15))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .accessibilityIdentifier("host-chooser.empty")
                        } else {
                            ForEach(options) { host in
                                row(host)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.secondary)
            TextField(
                "",
                text: $query,
                prompt: Text("Search hosts...").foregroundStyle(ClaudePalette.secondary)
            )
            .font(typography.sans(15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier("host-chooser.search")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(ClaudePalette.chip, in: .rect(cornerRadius: 12))
    }

    private func row(_ host: DeepLinkHost) -> some View {
        Button {
            Haptics.selection()
            onChoose(host)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(host.isCurrent ? ClaudePalette.successInk : ClaudePalette.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.label)
                        .font(typography.sans(17, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    Text(host.detail)
                        .font(typography.mono(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: host.isRelay ? "lock.shield" : "server.rack")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56, alignment: .leading)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("host-chooser.row.\(host.detail)")
    }
}
#endif
