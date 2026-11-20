import SwiftUI

/// Content text size on top of Dynamic Type, and code font size. Both are relative steps stored
/// as their raw value; `RootView` shifts Dynamic Type by them, so settings apply live without
/// rebuilding the shell.
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

        /// Dynamic Type steps on top of the system size (S = −1, M = 0, L = +1, XL = +2).
        public var step: Int {
            switch self {
            case .small: -1
            case .medium: 0
            case .large: 1
            case .xlarge: 2
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

        /// Dynamic Type steps on top of the system size (S = −1, M = 0, L = +1, XL = +2).
        public var step: Int {
            switch self {
            case .small: -1
            case .medium: 0
            case .large: 1
            case .xlarge: 2
            }
        }

        /// The terminal keeps an explicit multiplier (SwiftTerm wants a `UIFont` size).
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

    public static func codeMultiplier(_ defaults: UserDefaults = .standard) -> CGFloat {
        code(defaults).multiplier
    }
}
