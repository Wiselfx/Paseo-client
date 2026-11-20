#if canImport(UIKit)
/// Keys shared by the app's composition root and the in-app settings sheet.
/// The appearance key is `ClaudeAppearance.storageKey` (one key, one owner).
public enum PaseoSettingsKeys {
    public static let yourName = "paseo.yourName"
    public static let haptics = "paseo.haptics"
    public static let mascot = "paseo.mascot.enabled"
    /// Off by default (`bool(forKey:)` is false when unset): agent titles stay
    /// generic on the Lock Screen and system surfaces. In-app Spotlight search
    /// still indexes titles (on-device, never leaves the phone) — see the
    /// directory writer for why.
    public static let showAgentNames = "paseo.privacy.showAgentNames"
    /// Off by default: allow/deny actions never appear on notifications unless
    /// the reader opts in (G19).
    public static let notificationActions = "paseo.notifications.actions"
}
#endif
