#if canImport(UIKit)
    import CoreText
    import Foundation

    /// Registers the bundled Anthropic faces and the Newsreader serif fallback for this process.
    /// Public so Paseo's DesignSystem can use it.
    @MainActor public enum ClaudeFontResources {
        /// PostScript names read from the bundled files with `fc-scan`, not guessed.
        public static let anthropicSans = "AnthropicSansWebVariable-TextRegular"
        public static let anthropicSerif = "AnthropicSerifWebVariable-TextRegular"
        public static let anthropicMono = "AnthropicMonoWebWeb-Regular"
        public static let newsreader = "Newsreader16pt-Regular"

        private static let registration: Void = {
            for name in [
                "Newsreader", "Newsreader-Italic",
                "AnthropicSansWebText", "AnthropicSerifWebText", "AnthropicMonoWeb",
            ] {
                if let url = Bundle.module.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                }
            }
        }()

        public static func register() { _ = registration }

        /// CoreText returns a substitute face when the requested one is not registered; compare the
        /// PostScript names so a missing file falls back instead of silently drawing Helvetica.
        nonisolated static func isAvailable(_ postScriptName: String) -> Bool {
            let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
            let resolved = CTFontCopyPostScriptName(font) as String
            return resolved.caseInsensitiveCompare(postScriptName) == .orderedSame
        }
    }
#endif
