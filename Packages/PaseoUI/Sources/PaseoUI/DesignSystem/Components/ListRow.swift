#if canImport(UIKit)
import SwiftUI

/// A standard list row: an optional leading glyph, title and subtitle, and one trailing
/// accessory. Rows with an action get a `PressableRowStyle` button.
struct ListRow: View {
    enum Accessory {
        case none
        case chevron
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
            accessoryView
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
        case .checkmark(let isOn):
            if isOn {
                Image(systemName: "checkmark")
                    .font(.glyph(.regular, weight: .semibold))
                    .foregroundStyle(Palette.selection)
                    .accessibilityHidden(true)
            }
        case .value(let text):
            Text(text)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        case .toggle(let isOn):
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Palette.toggleTint)
        case .badge(let text):
            StatePill(text, tone: .neutral)
        case .progress:
            InlineProgress()
        }
    }
}

/// The old name for `ListRow`; unconverted call sites keep working.
@available(*, deprecated, message: "Use ListRow")
struct SheetRow: View {
    let title: String
    var symbol: String?
    var detail: String?
    var value: String?
    var checked = false
    var chevron = false
    var badge: String?
    var action: () -> Void

    var body: some View {
        ListRow(
            title: title,
            subtitle: detail,
            systemImage: symbol,
            accessory: accessory,
            action: action
        )
    }

    private var accessory: ListRow.Accessory {
        if let value { return .value(value) }
        if checked { return .checkmark(true) }
        if let badge { return .badge(badge) }
        if chevron { return .chevron }
        return .none
    }
}

#Preview("Light") {
    VStack(spacing: 0) {
        ListRow(title: "Title", subtitle: "Subtitle line", systemImage: "person")
        ListRow(title: "Chevron row", systemImage: "folder", accessory: .chevron, action: {})
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
