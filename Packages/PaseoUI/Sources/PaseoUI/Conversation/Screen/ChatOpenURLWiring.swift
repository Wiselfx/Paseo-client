#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// Reads `\.openURL` in its own body (W1). `ChatScreen` read it itself, and the value is rebuilt by the
/// hosting controller whenever the input session changes, so every keystroke re-ran the screen's body
/// (21 runs a window with no input of its own changing). Here only this modifier re-evaluates.
struct ChatOpenURLWiring: ViewModifier {
    let controller: ChatController
    @Environment(\.openURL) private var openURL
    @Environment(\.toast) private var toast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, controller.fileLinkAction(host: openURL))
            .onAppear {
                controller.openURLFromEnvironment = { url in openURL(url) }
                controller.toastCenter = toast
                controller.reduceMotion = reduceMotion
            }
            .onChange(of: reduceMotion) { _, value in controller.reduceMotion = value }
            .onChange(of: toast.map(ObjectIdentifier.init)) { _, _ in controller.toastCenter = toast }
    }
}
#endif
