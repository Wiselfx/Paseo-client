#if canImport(UIKit)
import SwiftUI

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
#endif
