#if canImport(UIKit)
/// Keys shared by the app's composition root and the in-app settings sheet.
/// The appearance key is `ClaudeAppearance.storageKey` (one key, one owner).
public enum PaseoSettingsKeys {
    public static let yourName = "paseo.yourName"
    public static let haptics = "paseo.haptics"
    public static let mascot = "paseo.mascot.enabled"
}
#endif
