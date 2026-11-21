#if canImport(UIKit)
import SwiftUI

/// A standard list row: an optional leading glyph, title and subtitle, and one trailing
/// accessory. Rows with an action get a `PressableRowStyle` button.
struct ListRow: View {
    enum Accessory {
        case none
        case chevron
        /// An optional value and the push chevron, both inside the row's own padding. A
        /// `NavigationLink`'s system chevron sits at the cell edge, out of line with the value
        /// text and the separators; `PageLink` uses this instead.
        case disclosure(String?)
        case checkmark(Bool)
        case value(String)
        case toggle(Binding<Bool>)
        case badge(String)
        case progress
    }

    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let accessory: Accessory
    private let action: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        accessory: Accessory = .none,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                row
            }
            .buttonStyle(.paseoRow)
            .accessibilityElement(children: .combine)
            // The checkmark is hidden from VoiceOver, so the selected state is announced instead.
            .accessibilityAddTraits(isChecked ? .isSelected : [])
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.body))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ListRowAccessoryView(accessory: accessory)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
        .contentShape(.rect)
        // The separator starts under the title, not under the icon (D3 §2).
        .alignmentGuide(.listRowSeparatorLeading) { _ in titleLeading }
    }

    private var isChecked: Bool {
        if case .checkmark(true) = accessory { true } else { false }
    }

    /// Where the title starts: past the glyph and its gap when the row has one.
    private var titleLeading: CGFloat {
        systemImage == nil ? Space.lg : Space.lg + 24 + Space.md
    }
}

#Preview("Light") {
    VStack(spacing: 0) {
        ListRow(title: "Title", subtitle: "Subtitle line", systemImage: "person")
        ListRow(title: "Chevron row", systemImage: "folder", accessory: .chevron, action: {})
        ListRow(title: "Disclosure", systemImage: "folder", accessory: .disclosure("Light"), action: {})
        ListRow(title: "Checkmark", accessory: .checkmark(true), action: {})
        ListRow(title: "Value", accessory: .value("12 KB"), action: {})
        ListRow(title: "Badge", accessory: .badge("3"))
        ListRow(title: "Working", accessory: .progress)
        ListRow(title: "Toggle", accessory: .toggle(.constant(true)))
        ListRow(title: "Disabled-looking", subtitle: "No action")
    }
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: 0) {
        ListRow(title: "Title", subtitle: "Subtitle line", systemImage: "person")
        ListRow(title: "Chevron row", systemImage: "folder", accessory: .chevron, action: {})
        ListRow(title: "Toggle", accessory: .toggle(.constant(true)))
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
