#if canImport(UIKit)
import SwiftUI

/// One inline message under or above a list: info, warning or failure, with an optional action
/// and an optional dismiss.
struct InlineBanner: View {
    enum Kind {
        case info
        case warning
        case failure
    }

    private let kind: Kind
    private let title: String
    private let message: String?
    private let systemImage: String?
    private let action: (String, () -> Void)?
    private let onDismiss: (() -> Void)?

    init(
        _ kind: Kind,
        title: String,
        message: String? = nil,
        systemImage: String? = nil,
        action: (String, () -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(titleColor)
                if let message {
                    Text(message)
                        .font(.paseo(.footnote))
                        .foregroundStyle(titleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action.0, action: action.1)
                    .font(.paseo(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .buttonStyle(.plain)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.glyph(.small, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(titleColor)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, onDismiss == nil ? Space.md : 0)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: .rect(cornerRadius: Radius.md))
    }

    private var fill: Color {
        switch kind {
        case .info, .warning: Palette.chip
        case .failure: Palette.failureInk.opacity(0.10)
        }
    }

    private var titleColor: Color {
        switch kind {
        case .info, .warning: Palette.secondaryInk
        case .failure: Palette.failureInk
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info: Palette.secondaryInk
        case .warning: Palette.warning
        case .failure: Palette.failureInk
        }
    }
}

#Preview("Light") {
    VStack(spacing: Space.md) {
        InlineBanner(.info, title: "Info banner", message: "Detail.", systemImage: "info.circle")
        InlineBanner(.warning, title: "Warning banner", systemImage: "exclamationmark.triangle")
        InlineBanner(
            .failure, title: "Failure banner", message: "Something went wrong.",
            systemImage: "xmark.octagon", action: ("Retry", {}), onDismiss: {})
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: Space.md) {
        InlineBanner(.warning, title: "Warning banner", systemImage: "exclamationmark.triangle")
        InlineBanner(.failure, title: "Failure banner", message: "Something went wrong.")
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
