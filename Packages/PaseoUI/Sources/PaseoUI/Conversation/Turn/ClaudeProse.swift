#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Assistant prose: the serif Markdown renderer, one place for the theme.
/// `isStreaming` lets DSH's new-text reveal fade in only what actually arrives while you watch.
struct ClaudeProse: View {
    var markdown: String
    var onAction: (MarkdownAction) -> Void
    /// True while the producing turn is running — assistant prose arriving live fades in.
    var isStreaming: Bool = false

    var body: some View {
        let _ = PaseoPerf.body("Prose")
        let _ = PaseoPerf.why(Self.self)
        ClaudeRevealProse(
            markdown: markdown, theme: Self.theme(), onAction: onAction,
            isStreaming: isStreaming,
            imageContent: proseImageContent)
    }

    /// `![alt](url)` → `ProseMarkdownImage`; remote hosts and workspace paths both ride the
    /// shared `MediaPipeline`. Always non-nil so prose images render instead of degrading
    /// to text.
    private var proseImageContent: (MarkdownImage) -> AnyView {
        { image in
            AnyView(ProseMarkdownImage(image: image))
        }
    }

    static func theme(bodySize: CGFloat = Typography.chatBodySize) -> ClaudeMarkdownTheme {
        // Claude iOS chats at a 17 pt serif body (V5); the markdown *file preview* keeps the
        // research document's 14 pt, because UX-SPEC §6 freezes those previews.
        let chat = bodySize >= Typography.chatBodySize
        var theme = ClaudeMarkdownTheme(serifName: ProseFonts.serifName, bodySize: bodySize)
        theme.foreground = Palette.ink
        theme.secondary = Palette.secondaryInk
        theme.link = Palette.proseLink
        theme.codeBackground = Palette.codeSurface
        theme.inlineCodeBackground = Palette.inlineCodeFill
        theme.inlineCodeForeground = Palette.ink
        theme.codeFont = ProseFonts.mono(size: chat ? 15 : 13)
        theme.blockSpacing = chat ? 14 : 12
        theme.lineSpacing = chat ? 8 : 9 // chat: 17 / ~25; previews: 14 / 23
        return theme
    }
}
#endif
