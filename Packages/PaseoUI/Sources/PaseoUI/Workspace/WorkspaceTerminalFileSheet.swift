#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The target of a terminal local link: `path:line[:col]` (absolute, `~/` or workspace-relative).
struct TerminalLinkedFile: Identifiable {
    let path: String
    let line: Int?
    let col: Int?

    var id: String { "\(path):\(line ?? 0):\(col ?? 0)" }

    /// Sent as-is: the daemon expands `~/` against the host's home and resolves relative paths
    /// against the workspace cwd (upstream `file-explorer/service.ts` → `resolvePathFromBase`).
    /// This device's home directory means nothing on the host.
    var resolvedPath: String { path }
}

/// A read-only file view opened from a terminal local link: mono text, line numbers, the
/// requested line centered and highlighted. Text files only; binary/too-large show a calm note.
struct WorkspaceTerminalFileSheet: View {
    let checkout: CheckoutStore
    let target: TerminalLinkedFile

    @State private var text: String?
    @State private var failure: String?
    @State private var isLoading = false


    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        SheetScaffold(WorkspaceFileFormat.lastComponent(target.path), detents: .mediumLarge) {
            Group {
                if let text {
                    linkedContent(text)
                } else if let failure {
                    failureView(failure)
                } else {
                    LoadingState()
                }
            }
        }
        .task { await load() }
    }

    private func linkedContent(_ text: String) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let number = index + 1
                        HStack(spacing: 10) {
                            Text(verbatim: String(number))
                                .font(.paseo(.codeCaption))
                                .foregroundStyle(Palette.captionInk)
                                .frame(width: 34, alignment: .trailing)
                            Text(line)
                                .font(.paseo(.codeSmall))
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 1.5)
                        .background(
                            target.line == number
                                ? Palette.chip
                                : Color.clear)
                        .id(number)
                    }
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let line = target.line, line > 0 {
                    proxy.scrollTo(line, anchor: .center)
                }
            }
        }
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
        isLoading = true
        defer { isLoading = false }
        await files.read(target.resolvedPath)
        if let file = files.file, let text = file.textContent {
            self.text = text
            self.failure = nil
        } else {
            self.text = nil
            self.failure = files.error ?? "This file can't be shown here."
        }
    }
}
#endif
