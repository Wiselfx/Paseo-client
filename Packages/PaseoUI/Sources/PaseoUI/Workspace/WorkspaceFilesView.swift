#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Contract for ticket M3b: the "Files" page of the workspace panel (`WorkspacePanel`).
/// The panel constructs it with exactly these properties; M3b replaces the body.
struct WorkspaceFilesView: View {
    let checkout: CheckoutStore

    @State private var stack: [WorkspaceFilesRoute] = []
    private let typography = ClaudeTypography()

    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        Group {
            if let route = stack.last {
                page(route)
            } else {
                directoryList(path: "")
            }
        }
    }

    @ViewBuilder private func page(_ route: WorkspaceFilesRoute) -> some View {
        switch route {
        case .directory(let path):
            directoryList(path: path)
        case .file(let path):
            WorkspaceFileViewer(
                checkout: checkout, relPath: path, onBack: { stack.removeLast() },
                backLabel: backLabel(for: path))
            .id(path)
        }
    }

    private func directoryList(path: String) -> some View {
        WorkspaceFilesDirectoryList(
            checkout: checkout, relPath: path,
            onBack: path.isEmpty ? nil : { stack.removeLast() },
            onOpenDirectory: { path in
                if stack.last != .directory(path) { stack.append(.directory(path)) }
            },
            onOpenFile: { path in
                if stack.last != .file(path) { stack.append(.file(path)) }
            })
        // A distinct identity per directory: fresh state, fresh `onAppear`, no stale rows.
        .id(path)
    }

    /// The folder a file lives in, as the back label; "Files" at the root.
    private func backLabel(for path: String) -> String {
        let containing = WorkspaceFileFormat.containingDirectory(path)
        guard !containing.isEmpty else { return "Files" }
        return WorkspaceFileFormat.lastComponent(containing)
    }
}

/// One generation counter shared by the Files pages: only the newest refresh's result is
/// trusted, so two pages can never render each other's listing. All Files state lives on the
/// main actor.
@MainActor private enum WorkspaceFilesRefresh {
    static var generation = 0
}

/// A push destination in the page's hand-rolled stack. Directories open in place; files open the
/// viewer. Hashable for the `@State` stack only.
enum WorkspaceFilesRoute: Hashable {
    case directory(String) // workspace-relative path; "" is the root and never appears as a route
    case file(String)
}

/// One directory's rows: the back row when nested, then folders first and files after (the store
/// sorts), pull-to-refresh, and a calm error with Retry when the read fails.
private struct WorkspaceFilesDirectoryList: View {
    let checkout: CheckoutStore
    let relPath: String
    let onBack: (() -> Void)?
    let onOpenDirectory: (String) -> Void
    let onOpenFile: (String) -> Void

    /// The listing of this page's directory, captured when this page's refresh completed. The
    /// store keeps a single listing, so pages snapshot it rather than watch it change.
    @State private var listing: Result<[FileExplorerEntry], String>?
    @State private var toast: String?
    private let typography = ClaudeTypography()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "Mention in chat" from a row's long-press; nil disables the action.
    @Environment(\.mentionInChat) private var mentionInChat

    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeDivider()
            content
        }
        .onAppear { Task { await refresh() } }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: Header row

    private var header: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button {
                    Haptics.selection()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text(backTitle).font(typography.sans(13)).lineLimit(1)
                    }
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .accessibilityLabel("Back to \(backTitle)")
            } else {
                Text("Files")
                    .font(typography.sans(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .padding(.horizontal, 4)
            }
            Spacer(minLength: 8)
            if files.phase == .loading {
                ProgressView().controlSize(.mini)
            }
            Button {
                Haptics.selection()
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var backTitle: String {
        let parent = WorkspaceFileFormat.containingDirectory(relPath)
        guard !parent.isEmpty else { return "Files" }
        return WorkspaceFileFormat.lastComponent(parent)
    }

    private func refresh() async {
        WorkspaceFilesRefresh.generation += 1
        let token = WorkspaceFilesRefresh.generation
        await files.list(relPath.isEmpty ? nil : relPath)
        // A newer refresh (a sibling page, or a faster pull-to-refresh) owns the store's listing
        // now; showing anything from it here would paint the wrong directory.
        guard token == WorkspaceFilesRefresh.generation else { return }
        if case .failed(let message) = files.phase {
            listing = .failure(message)
        } else {
            listing = .success(files.entries)
        }
    }

    // MARK: Rows

    @ViewBuilder private var content: some View {
        switch listing {
        case nil:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let message):
            errorView(message)
        case .success(let entries):
            if entries.isEmpty { emptyView } else { list(entries) }
        }
    }

    private func list(_ entries: [FileExplorerEntry]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        ClaudeDivider().padding(.leading, 46)
                    }
                    row(entry)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await refresh() }
    }

    private func row(_ entry: FileExplorerEntry) -> some View {
        Button {
            Haptics.selection()
            if entry.isDirectory { onOpenDirectory(entry.path) } else { onOpenFile(entry.path) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(entry.isDirectory ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let meta = meta(entry) {
                        Text(meta)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !entry.isDirectory {
                Button("Mention in chat", systemImage: "at") {
                    mentionInChat?(relative(entry))
                }
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = absolute(entry)
                showToast("Path copied")
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = relative(entry)
                showToast("Relative path copied")
            }
        }
        .accessibilityLabel(entry.isDirectory ? "Folder \(entry.name)" : "File \(entry.name)")
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Text("Empty folder")
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("There is nothing to show here yet.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(message)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                Haptics.selection()
                Task { await refresh() }
            } label: {
                Text("Retry")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(ClaudePalette.chip, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }

    // MARK: Path helpers

    private func relative(_ entry: FileExplorerEntry) -> String {
        WorkspaceFileFormat.relativePath(entry.path, cwd: checkout.cwd)
    }

    private func absolute(_ entry: FileExplorerEntry) -> String {
        entry.path.hasPrefix("/") ? entry.path : checkout.cwd + "/" + relative(entry)
    }

    private func meta(_ entry: FileExplorerEntry) -> String? {
        WorkspaceFileFormat.metaLine(size: entry.size, modifiedAt: entry.modifiedAt)
    }
}
#endif
