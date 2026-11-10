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
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
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
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small))
                .foregroundStyle(Palette.tertiaryInk)
            TextField(
                "",
                text: $query,
                prompt: Text("Search hosts...").foregroundStyle(Palette.secondaryInk)
            )
            .font(.paseo(.callout))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier("host-chooser.search")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
    }

    private func row(_ host: DeepLinkHost) -> some View {
        Button {
            Haptics.selection()
            onChoose(host)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(host.isCurrent ? Palette.successInk : Palette.secondaryInk.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.label)
                        .font(.paseo(.body, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(host.detail)
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: host.isRelay ? "lock.shield" : "server.rack")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56, alignment: .leading)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("host-chooser.row.\(host.detail)")
    }
}
#endif
