#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The answer footer's fork control: one button opening the target menu (upstream
/// `assistant-fork-menu.tsx:100-121`). Labels are `en.ts:334-336`, verbatim.
///
/// While a target is in flight the trigger turns into a spinner and is disabled, so neither item
/// can start a second fork. Upstream puts the spinner **inside** the pending item and keeps it
/// enabled; a SwiftUI menu item cannot host a `ProgressView`, so the spinner lives on the trigger.
struct ClaudeForkMenu: View {
    /// False hides the workspace target: this host cannot create one, so offering it would only
    /// fail after the tap (E3 §2). Declared before `onFork` so the trailing closure still binds
    /// to it.
    var allowsWorkspace = true
    var onFork: (ClaudeForkTarget) async -> Void
    @State private var pending: ClaudeForkTarget?

    var body: some View {
        Menu {
            Button("Fork in a new tab", systemImage: "arrow.branch") { run(.tab) }
                .disabled(pending != nil)
            if allowsWorkspace {
                Button("Fork in a new workspace", systemImage: "square.on.square.dashed") {
                    run(.workspace)
                }
                .disabled(pending != nil)
            }
        } label: {
            ClaudeTurnActionGlyph(systemImage: "arrow.branch", busy: pending != nil)
        }
        .buttonStyle(.plain)
        .disabled(pending != nil)
        .accessibilityLabel("Fork chat from here")
    }

    /// Starts one fork at a time and holds the button down until it lands.
    private func run(_ target: ClaudeForkTarget) {
        guard pending == nil else { return }
        pending = target
        Task {
            await onFork(target)
            pending = nil
        }
    }
}
#endif
