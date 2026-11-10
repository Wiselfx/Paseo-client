#if canImport(UIKit)
import SwiftUI

/// One page in a sheet's stack: the inset-grouped list restyled onto the palette (PLAN §RE).
/// Shared by Settings, Schedules, History and Search, which all present lists the same way.
/// R-5: one component, not a copy per screen.
struct PageList<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }
}

extension View {
    /// A page row: the panel fill, with the row keeping its own inner padding.
    func panelRow(_ background: Color = Palette.panel) -> some View {
        listRowBackground(background)
            .listRowInsets(EdgeInsets())
    }

    /// A pushed page's chrome: inline title, palette background. A sheet root keeps its own title.
    func inlinePageTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Palette.background)
    }
}

/// A pushed page row: the row drawn here, the system's push behind it (D3 §2).
///
/// `NavigationLink` adds its own chevron at the cell's trailing edge, outside the row's padding
/// and out of line with the value text and the separators — with `.panelRow()` it reads as a
/// chevron hanging off the row. `PageLink` keeps the push, the row highlight and VoiceOver's
/// link, and lets `ListRow` draw the chevron inside its own padding instead.
struct PageLink<Value: Hashable>: View {
    private let value: Value
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let detail: String?

    init(
        _ value: Value,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        detail: String? = nil
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        ListRow(
            title: title, subtitle: subtitle, systemImage: systemImage,
            accessory: .disclosure(detail)
        )
        // The row is drawn, not touched: the link underneath owns the tap, the press highlight
        // and the accessibility element.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background { pushLink }
        .panelRow()
        .alignmentGuide(.listRowSeparatorLeading) { _ in titleLeading }
    }

    /// A clear label, so the link fills the row: an empty one would size to nothing.
    private var pushLink: some View {
        NavigationLink(value: value) { Color.clear }
            .opacity(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [title, subtitle, detail].compactMap { $0 }.joined(separator: ", ")
    }

    private var titleLeading: CGFloat {
        systemImage == nil ? Space.lg : Space.lg + 24 + Space.md
    }
}

/// A `Section` header inside a `PageList`: sentence case, footnote semibold, `secondaryInk`,
/// flush with the row text. The list owns the vertical rhythm, the row owns the leading edge.
struct PageSectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.lg)
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
