#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shown when Microphone or Speech Recognition is denied: a pointer to Settings.
struct ComposerDictationDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        InlineBanner(
            .failure, title: "Dictation is off.",
            message: "Enable Microphone and Speech Recognition in Settings.",
            systemImage: "mic.slash",
            action: ("Settings", {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }))
            .accessibilityIdentifier("composer.dictation.settings")
    }
}
#endif
