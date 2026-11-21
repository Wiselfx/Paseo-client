#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// M20: the deep-link host chooser, upstream `hosts/host-chooser.tsx`. Searchable, local-first
/// order, "No matching hosts" empty state (upstream strings, hardcoded there exactly as here:
/// title `Choose host` at `:85`, placeholder `Search hosts...` at `:248`, empty state at `:263`).
/// Rows show the label and the daemon identity, as upstream's `HostChooserRow` does (`:95-137`).
public struct HostChooserSheet: View {
    private let hosts: [DeepLinkHost]
    private let onChoose: (DeepLinkHost) -> Void
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
        SheetScaffold("Choose host", detents: .mediumLarge) {
            VStack(alignment: .leading, spacing: Space.md) {
                searchField
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        if options.isEmpty {
                            EmptyState(title: "No matching hosts")
                                .padding(.vertical, 18)
                                .accessibilityIdentifier("host-chooser.empty")
                        } else {
                            ForEach(options) { host in
                                row(host)
                            }
                        }
                    }
                    .padding(.bottom, Space.sm)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.lg)
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small))
                .foregroundStyle(Palette.tertiaryInk)
            TextField(
                "Search hosts",
                text: $query,
                prompt: Text("Search hosts...").foregroundStyle(Palette.secondaryInk)
            )
            .font(.paseo(.callout))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier("host-chooser.search")
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: 42)
        .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
    }

    private func row(_ host: DeepLinkHost) -> some View {
        Button {
            onChoose(host)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: host.isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.glyph(.small))
                    .foregroundStyle(host.isCurrent ? Palette.successInk : Palette.tertiaryInk)
                    .frame(width: 14)
                    .accessibilityHidden(true)
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
        .accessibilityAddTraits(host.isCurrent ? .isSelected : [])
        .accessibilityIdentifier("host-chooser.row.\(host.detail)")
    }
}
#endif
