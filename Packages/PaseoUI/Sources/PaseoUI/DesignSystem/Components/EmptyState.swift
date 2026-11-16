#if canImport(UIKit)
import SwiftUI

/// A quiet centered state: optional symbol, title, detail and one secondary action.
struct EmptyState: View {
    private let systemImage: String?
    private let title: String
    private let message: String?
    private let action: (title: String, run: () -> Void)?

    init(
        systemImage: String? = nil,
        title: String,
        message: String? = nil,
        action: (title: String, run: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.glyph(.xlarge, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(.paseoSecondary)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Light") {
    VStack {
        EmptyState(
            systemImage: "person.2", title: "No subagents",
            message: "Subagents your provider runs for this agent appear here.")
        EmptyState(
            systemImage: "tray", title: "Nothing here", message: "Detail line.",
            action: (title: "Retry", run: {}))
        EmptyState(title: "No title glyph")
    }
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack {
        EmptyState(
            systemImage: "person.2", title: "No subagents",
            message: "Subagents your provider runs for this agent appear here.")
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
