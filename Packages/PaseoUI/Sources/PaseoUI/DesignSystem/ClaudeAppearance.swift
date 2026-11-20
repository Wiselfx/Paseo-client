import SwiftUI

/// The app's appearance choice, persisted as its raw value.
public enum ClaudeAppearance: String, CaseIterable, Sendable {
    case system = "System", light = "Light", dark = "Dark", pureBlack = "Pure black"

    public static let storageKey = "paseo.appearance"

    /// The scheme the device should render; Pure black is a dark scheme.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .pureBlack: .dark
        }
    }

    /// True when the pure-black palette should render. `RootView` publishes it through the
    /// `\.pureBlack` trait, so a switch redraws live.
    public var isPureBlack: Bool { self == .pureBlack }
}
