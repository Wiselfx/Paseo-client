#if canImport(UIKit)
import PaseoStore

extension SpeechFieldSource {
    /// "Set by …" when an env var decides the field.
    var setByHint: String? {
        guard let envVar else { return nil }
        return "Set by \(envVar)"
    }
}
#endif
