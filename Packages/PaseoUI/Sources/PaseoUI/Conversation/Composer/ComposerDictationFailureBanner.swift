#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Upstream `message.dictation.failed`: "Dictation failed: {{error}}", with `retry`.
struct ComposerDictationFailureBanner: View {
    let failure: DictationController.Failure
    let onRetry: () -> Void

    var body: some View {
        InlineBanner(
            .failure, title: failure.title, message: failure.message, systemImage: "mic.slash",
            action: ("Retry dictation", onRetry))
            .accessibilityIdentifier("composer.dictation.failed")
    }
}
#endif
