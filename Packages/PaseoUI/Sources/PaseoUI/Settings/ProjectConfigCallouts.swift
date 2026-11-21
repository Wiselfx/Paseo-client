#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The stale-file and failed-write cards, chosen from the config store's error state.
struct ProjectConfigCallouts: View {
    let store: ProjectConfigStore
    let onSave: () -> Void
    let onReload: () -> Void

    var body: some View {
        if store.stale, store.error != nil {
            ProjectConfigCallout(
                title: "This file changed on the host.",
                detail: "Your edits were not saved. Reloading shows the latest paseo.json.",
                actionLabel: "Reload",
                action: onReload)
        }
        if !store.stale, let error = store.error {
            ProjectConfigCallout(
                title: "The change couldn't be saved.",
                detail: error.userMessage,
                actionLabel: "Try again",
                action: onSave)
        } else if let sendError = store.sendError {
            ProjectConfigCallout(
                title: "The change couldn't be saved.",
                detail: sendError,
                actionLabel: "Reload",
                action: onReload)
        }
    }
}
#endif
