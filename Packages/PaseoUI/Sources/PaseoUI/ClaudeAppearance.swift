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

    /// True when the pure-black palette should render. Read at Color-creation time (the palette
    /// short-circuits its dynamic provider on this), so theme changes apply on the next draw.
    public var isPureBlack: Bool { self == .pureBlack }

    /// Whether the stored appearance is Pure black. Unset/unknown values read as false, so
    /// Light/Dark/System behave exactly as before.
    public static var pureBlackActive: Bool {
        UserDefaults.standard.string(forKey: storageKey) == ClaudeAppearance.pureBlack.rawValue
    }
}

/// Content text size on top of Dynamic Type, and code font size. Both are relative steps stored
/// as their raw value; the typography reads them at Font-creation time and the app shell forces
/// a rebuild on change, so settings apply live.
public enum ClaudeTextScale {
    public enum Content: String, CaseIterable, Sendable {
        case small = "S", medium = "M", large = "L", xlarge = "XL"

        public var label: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .xlarge: "Extra large"
            }
        }

        var multiplier: CGFloat {
            switch self {
            case .small: 0.875
            case .medium: 1.0
            case .large: 1.15
            case .xlarge: 1.3
            }
        }
    }

    public enum Code: String, CaseIterable, Sendable {
        case small = "S", medium = "M", large = "L", xlarge = "XL"

        public var label: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .xlarge: "Extra large"
            }
        }

        var multiplier: CGFloat {
            switch self {
            case .small: 0.875
            case .medium: 1.0
            case .large: 1.15
            case .xlarge: 1.3
            }
        }
    }

    public static let contentStorageKey = "paseo.contentTextSize"
    public static let codeStorageKey = "paseo.codeFontSize"

    public static func content(_ defaults: UserDefaults = .standard) -> Content {
        Content(rawValue: defaults.string(forKey: contentStorageKey) ?? "") ?? .medium
    }

    public static func code(_ defaults: UserDefaults = .standard) -> Code {
        Code(rawValue: defaults.string(forKey: codeStorageKey) ?? "") ?? .medium
    }

    public static func contentMultiplier(_ defaults: UserDefaults = .standard) -> CGFloat {
        content(defaults).multiplier
    }

    public static func codeMultiplier(_ defaults: UserDefaults = .standard) -> CGFloat {
        code(defaults).multiplier
    }
}
