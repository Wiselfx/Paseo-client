#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

/// The app-wide typography facade: prose and Markdown keep naming sizes (they are measured
/// against their own body size), everything else uses `Font.paseo(_:)`.
public struct ClaudeTypography: Sendable {
    public static let anthropicSans = ClaudeFontResources.anthropicSans
    public static let anthropicSerif = ClaudeFontResources.anthropicSerif
    public static let anthropicMono = ClaudeFontResources.anthropicMono
    public static let newsreader = ClaudeFontResources.newsreader

    public init() {}

    /// Assistant prose, greeting, sidebar title, headings.
    public func serif(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        ProseFonts.serif(size: size, relativeTo: style, weight: weight, italic: italic)
    }

    /// UI text, buttons, composer, sidebar rows.
    public func sans(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        ProseFonts.sans(size: size, relativeTo: style, weight: weight)
    }

    /// Code, tool output, diffs.
    public func mono(
        _ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular
    ) -> Font {
        ProseFonts.mono(size: size, relativeTo: style, weight: weight)
    }

    /// The name the Markdown theme needs: the bundled serif (Newsreader).
    public var resolvedSerifName: String { Typography.resolvedSerifName }
}
#endif
