import SwiftUI

/// A tappable header row that opens and closes a section, with a rotating chevron and a selection
/// tick. The building block of every collapsible thing in a turn.
public struct DisclosureHeader<Label: View>: View {
    @Binding var isExpanded: Bool
    var chevronLeading: Bool
    var label: Label

    public init(isExpanded: Binding<Bool>, chevronLeading: Bool = false, @ViewBuilder label: () -> Label) {
        _isExpanded = isExpanded
        self.chevronLeading = chevronLeading
        self.label = label()
    }

    public var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.28)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                if chevronLeading { chevron }
                label
                if !chevronLeading { chevron }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
    }
}

/// Rounded container with a hairline border, for work groups and tool output.
public struct Card<Content: View>: View {
    var content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
    }
}
