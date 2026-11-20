#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The conversation's card verbs; nil outside a conversation (previews, the draft screen).
    @Entry var richActions: RichActions?
}
// MARK: - Chrome

/// The card family's container (G1 §1.1): the panel surface, the 0.5 pt card border, the
/// 12 pt continuous radius — the same chrome `RichCard` drew, now in one place.
///
/// The content is a constructed value, never a builder: card initializers take values only
/// (R-2), so a card is built as `PaseoCard(content: HStack { ... })`, not as a trailing closure.
struct PaseoCard<Content: View>: View {
    let content: Content

    init(content: Content) {
        self.content = content
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.md)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
    }
}
// MARK: - Context menu

/// The card menu (G1 §1.2): every card offers the same items in the same order, and only the
/// ones that apply. A nil slot omits its item; the order below is the §1.2 order: Open, Share,
/// Copy, Save to Photos, Open externally, View source, Show in Files.
///
/// Local presentation (a sheet, a source toggle, an in-app browser) arrives as the `on…`
/// closures, which flip view-local state; cross-cutting verbs (copy, save, external open,
/// Show in Files) go through `RichActions` from the environment. No haptic here: the system
/// already plays one when a context menu appears.
extension View {
    func paseoCardMenu(
        openTitle: String? = nil,
        onOpen: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        copyTitle: String? = nil,
        copyText: String? = nil,
        saveImage: UIImage? = nil,
        externalTitle: String? = nil,
        externalURL: URL? = nil,
        viewSourceTitle: String? = nil,
        onViewSource: (() -> Void)? = nil,
        filePath: String? = nil
    ) -> some View {
        modifier(PaseoCardMenuModifier(
            openTitle: openTitle, onOpen: onOpen,
            onShare: onShare,
            copyTitle: copyTitle, copyText: copyText,
            saveImage: saveImage,
            externalTitle: externalTitle, externalURL: externalURL,
            viewSourceTitle: viewSourceTitle, onViewSource: onViewSource,
            filePath: filePath))
    }
}
// MARK: - Accessibility

extension View {
    /// One accessibility element per card (G1 §1.5): kind + title + meta. A card whose whole
    /// body is one action also takes the button trait; a card with several controls leaves its
    /// children visible and labels its regions instead.
    func paseoCardAccessibility(
        kind: String, title: String, meta: String? = nil, isButton: Bool = false
    ) -> some View {
        self.accessibilityElement(children: .combine)
            .accessibilityLabel(
                ([kind, title] + (meta.map { [$0] } ?? [])).filter { !$0.isEmpty }
                    .joined(separator: ", "))
            .accessibilityAddTraits(isButton ? .isButton : [])
    }
}
#endif
