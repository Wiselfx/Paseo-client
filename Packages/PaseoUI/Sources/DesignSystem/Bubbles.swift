import ClaudeUI
import SwiftUI
import UIKit

/// What you said: a soft bubble on the trailing edge.
public struct UserBubble: View {
    var text: String
    var isPending: Bool
    public init(text: String, isPending: Bool = false) {
        self.text = text
        self.isPending = isPending
    }

    public var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Palette.userBubble, in: RoundedRectangle(cornerRadius: Metrics.bubbleRadius, style: .continuous))
                .opacity(isPending ? 0.6 : 1)
                .animation(.easeOut(duration: 0.2), value: isPending)
        }
    }
}

/// What the agent said: Markdown in the serif.
public struct Prose: View {
    var markdown: String
    var onOpenURL: (URL) -> Void

    public init(_ markdown: String, onOpenURL: @escaping (URL) -> Void) {
        self.markdown = markdown
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        ClaudeMarkdownView(markdown, theme: Typeset.markdown) { action in
            switch action {
            case .openLink(let url): onOpenURL(url)
            case .copyCode(let code):
                UIPasteboard.general.string = code
                Haptics.selection()
            default: break
            }
        }
    }
}
