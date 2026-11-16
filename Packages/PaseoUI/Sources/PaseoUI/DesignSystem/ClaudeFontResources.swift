#if canImport(UIKit)
    import CoreText
    import Foundation

    /// Registers the bundled open faces (Inter, Newsreader, JetBrains Mono) and the Anthropic
    /// files kept for the terminal and diff views for this process.
    /// Public so Paseo's DesignSystem can use it.
    public enum ClaudeFontResources {
        /// PostScript names read from the bundled files with `fc-scan`, not guessed.
        public static let anthropicSans = "AnthropicSansWebVariable-TextRegular"
        public static let anthropicSerif = "AnthropicSerifWebVariable-TextRegular"
        public static let anthropicMono = "AnthropicMonoWebWeb-Regular"
        /// Inter 4.1, SIL OFL 1.1: the default sans.
        public static let inter = "InterVariable"
        public static let interItalic = "InterVariableItalic"
        /// Newsreader, SIL OFL 1.1: the default serif.
        public static let newsreader = "Newsreader16pt-Regular"
        public static let newsreaderItalic = "Newsreader16pt-Italic"
        /// JetBrains Mono, SIL OFL 1.1: the default mono.
        public static let jetBrainsMono = "JetBrainsMono-Regular"
        public static let jetBrainsMonoItalic = "JetBrainsMono-Italic"

        private static let registration: Void = {
            // One call, one round trip to the font daemon, instead of nine; it runs before the first frame.
            let urls = [
                "InterVariable", "InterVariable-Italic",
                "Newsreader", "Newsreader-Italic",
                "JetBrainsMonoVariable", "JetBrainsMonoItalicVariable",
                "AnthropicSansWebText", "AnthropicSerifWebText", "AnthropicMonoWeb",
            ].compactMap { Bundle.module.url(forResource: $0, withExtension: "ttf") }
            guard !urls.isEmpty else { return }
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
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
