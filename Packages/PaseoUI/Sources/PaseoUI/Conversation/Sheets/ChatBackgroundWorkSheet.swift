#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The sheet that lists background work with a Stop affordance per stoppable item.
struct ChatBackgroundWorkSheet: View {
    let backgroundWork: BackgroundWorkStore

    @State private var pendingStop: BackgroundWorkItem?
    /// Bumped when a Stop is tapped, so the haptic is a sensory feedback of this view.
    @State private var stopPulse = 0

    private var canStop: Bool { backgroundWork.canStop }

    var body: some View {
        SheetScaffold("Background work", detents: .mediumLarge) {
            Group {
                if backgroundWork.items.isEmpty {
                    EmptyState(
                        systemImage: "gearshape.2",
                        title: "No background tasks",
                        message: "Background work your agent starts appears here."
                    )
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(backgroundWork.items) { item in
                                BackgroundWorkItemRow(
                                    item: item, canStop: canStop, onStop: { requestStop(item) })
                                if item.id != backgroundWork.items.last?.id {
                                    ClaudeDivider().padding(.leading, 52)
                                }
                            }
                            if let error = backgroundWork.error {
                                InlineBanner(.failure, title: error)
                                    .padding(.horizontal, Space.lg)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, Space.xs)
                    }
                }
            }
            .paseoFeedback(.light, trigger: stopPulse)
            .confirmationDialog(
                "Stop this background task?",
                item: $pendingStop,
                titleVisibility: .visible
            ) { item in
                Button("Stop", role: .destructive) {
                    performStop(item)
                    pendingStop = nil
                }
                Button("Cancel", role: .cancel) { pendingStop = nil }
            } message: { _ in
                Text("Its output will be discarded.")
            }
            .task { await backgroundWork.load() }
        }
    }

    /// A shell is stopped only after the confirmation; anything else stops straight away.
    private func requestStop(_ item: BackgroundWorkItem) {
        stopPulse += 1
        if item.kind == "shell" {
            pendingStop = item
        } else {
            performStop(item)
        }
    }

    private func performStop(_ item: BackgroundWorkItem) {
        // Refusals land in the store's `error`, rendered inline under the list.
        Task { _ = await backgroundWork.stop(itemId: item.id) }
    }
}
#endif
