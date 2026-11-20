import SwiftUI

/// The accent choice: Paseo green (default) or the Claude clay. It changes only the accent
/// tokens, never the theme; `RootView` publishes it through the `\.accent` trait, so a switch
/// redraws live.
public enum ClaudeAccent: String, CaseIterable, Sendable {
    case claude = "Claude", paseo = "Paseo"

    public static let storageKey = "paseo.accent"
}
