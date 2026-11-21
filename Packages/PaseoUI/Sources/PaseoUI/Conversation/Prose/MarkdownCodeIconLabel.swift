#if canImport(UIKit)
import SwiftUI

/// The label of an icon-only code action: a text-titled `Label`, so the title is the VoiceOver
/// and Voice Control name. The glyph keeps its 28 pt box inside the 44 pt tap target, and the
/// frame and content shape sit inside the label, where they enlarge the button's hit area.
struct MarkdownCodeIconLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .frame(width: Metrics.codeIconSize, height: Metrics.codeIconSize)
            .frame(width: Metrics.hitSize, height: Metrics.hitSize)
            .contentShape(.rect)
    }
}
#endif
