#if canImport(UIKit)
import SwiftUI

/// The marker in front of a list item: a bullet, the ordered number, or a task box. The task
/// state reads as "Completed" / "Not completed" to VoiceOver, which would otherwise read the
/// ☑ / ☐ glyphs as "ballot box with check".
struct MarkdownListMarker: View {
    /// The task state of the item; nil for a plain item.
    let checked: Bool?
    /// The first number of an ordered list; nil for a bullet list.
    let start: Int?
    /// The item's position in its list.
    let index: Int
    let theme: ClaudeMarkdownTheme

    private var glyph: String {
        checked.map { $0 ? "☑" : "☐" } ?? start.map { "\($0 + index)." } ?? "•"
    }

    private var spokenLabel: Text {
        if let checked { return checked ? Text("Completed") : Text("Not completed") }
        return Text(glyph)
    }

    var body: some View {
        Text(glyph).font(theme.bodyFont)
            .frame(minWidth: MarkdownMetrics.listMarkerMinWidth, alignment: .trailing)
            .accessibilityLabel(spokenLabel)
    }
}
#endif
