#if canImport(UIKit)
import Foundation
import NaturalLanguage

/// Loads the text system's language resources once, off the main thread, a few seconds after a screen
/// with a composer appears (W1).
///
/// The first time a text view becomes first responder, UIKit builds its word tagger and language
/// identifier on the main thread: sampled stalls of the first composer focus after a launch show
/// `CoreNLP::WordTagger::createWordTagger`, `SingletonResourceManager` file reads and
/// `langid_consume_string` inside the 330 to 450 ms. The resources are process-wide singletons backed
/// by files, so asking for them from a utility queue first leaves them built (and the files cached)
/// when the keyboard opens. Nothing is shown and no setting of the field is touched.
enum TextInputWarmup {
    private static let started = Locked(false)

    /// Idempotent. Call from a screen's `onAppear`; the work starts after `delay` seconds.
    static func start(after delay: Double = 3) {
        let first = started.withLock { flag -> Bool in
            defer { flag = true }
            return !flag
        }
        guard first else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            PaseoPerf.measure("warm.textinput") {
                let sample = "Hello, this is a short message with a few words. Check the file @notes.md please."
                let tagger = NLTagger(tagSchemes: [.lexicalClass, .language])
                tagger.string = sample
                tagger.enumerateTags(
                    in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .lexicalClass
                ) { _, _ in true }
                _ = NLLanguageRecognizer.dominantLanguage(for: sample)
            }
        }
    }
}

/// A value behind an unfair lock, for flags touched from any queue.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
#endif
