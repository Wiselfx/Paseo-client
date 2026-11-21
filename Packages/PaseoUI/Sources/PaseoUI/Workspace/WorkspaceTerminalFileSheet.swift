#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A read-only file view opened from a terminal local link: mono text, line numbers, the
/// requested line centered and highlighted. Text files only; binary/too-large show a calm note.
struct WorkspaceTerminalFileSheet: View {
    let checkout: CheckoutStore
    let target: TerminalLinkedFile

    /// The file split once at load, off the main actor, not on every body pass.
    @State private var lines: [String]?
    @State private var failure: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        SheetScaffold(WorkspaceFileFormat.lastComponent(target.path), detents: .mediumLarge) {
            Group {
                if let lines {
                    TerminalLinkedFileLines(lines: lines, targetLine: target.line)
                        .transition(.opacity)
                } else if let failure {
                    failureView(failure)
                        .transition(.opacity)
                } else {
                    LoadingState()
                        .transition(.opacity)
                }
            }
            // The file arrives a moment after the sheet does: it fades in where the spinner was
            // rather than snapping in under it.
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: lines != nil)
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: failure)
        }
        .task { await load() }
    }

    private func failureView(_ message: String) -> some View {
        EmptyState(
            systemImage: "exclamationmark.triangle",
            title: message,
            action: (title: "Try again", run: { Task { await load() } })
        )
        .padding(.horizontal, Space.xl)
    }

    private func load() async {
        await files.read(target.resolvedPath)
        if let file = files.file, let text = file.textContent {
            self.lines = await Task.detached { text.splitLines() }.value
            self.failure = nil
        } else {
            self.lines = nil
            self.failure = files.error ?? "This file can't be shown here."
        }
    }
}
#endif
