#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The "Files" page of the workspace panel (`WorkspacePanel`): a real navigation stack of
/// folders, so the system back button and the edge swipe pop one level at a time.
struct WorkspaceFilesView: View {
    let checkout: CheckoutStore

    /// Restored from `WorkspaceFilesLocation`, so the page reopens where it was left.
    @State private var path: [FilePathItem]
    /// The file pushed on top of the folder stack.
    @State private var openFile: String?
    /// Workspace-relative path of a file the Files page should flash and scroll to
    /// ("Reveal in Files page" from the viewer); consumed by the containing directory page.
    @State private var revealTarget: String?
    @Environment(\.shellDrawer) private var shellDrawer

    private var files: WorkspaceFiles { checkout.files }

    init(checkout: CheckoutStore) {
        self.checkout = checkout
        let saved = WorkspaceFilesLocation.load(checkout.workspaceId)
        _path = State(initialValue: saved.stack.map(FilePathItem.init(path:)))
        _openFile = State(initialValue: saved.openFile)
    }

    var body: some View {
        NavigationStack(path: $path) {
            directoryList(path: "")
                .navigationDestination(for: FilePathItem.self) { item in
                    directoryList(path: item.path)
                }
                .navigationDestination(item: $openFile) { relPath in
                    WorkspaceFileViewer(
                        checkout: checkout, relPath: relPath,
                        onBack: { openFile = nil },
                        backLabel: backLabel(for: relPath), onReveal: { reveal(relPath: relPath) })
                    .id(relPath)
                    // The viewer draws no canvas of its own; it must sit on the panel's, not on
                    // the window's black (E2 §5).
                    .background(Palette.panel)
                }
                // The panel header already owns the back chevron and the workspace title.
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
        // The Files page and every pushed folder/file share the panel canvas (E2 §5): without
        // this the window's black shows through in dark and pure black.
        .background(Palette.panel)
        .onAppear { shellDrawer?.panelHandlesBack = !path.isEmpty }
        .onChange(of: path) { _, newPath in
            shellDrawer?.panelHandlesBack = !newPath.isEmpty
            rememberLocation()
        }
        .onChange(of: openFile) { _, _ in
            // A file is a terminal destination; only folders make the stack "deeper".
            shellDrawer?.panelHandlesBack = !path.isEmpty
            rememberLocation()
        }
        .onDisappear {
            shellDrawer?.panelHandlesBack = false
            WorkspaceFilesLocation.flush(checkout.workspaceId)
        }
    }

    private func rememberLocation() {
        WorkspaceFilesLocation.setStack(
            path.map(\.path), openFile: openFile, in: checkout.workspaceId)
    }

    /// Pop the file off the stack; the containing directory page stays and consumes
    /// `revealTarget` to flash the row.
    private func reveal(relPath: String) {
        openFile = nil
        revealTarget = relPath
    }

    private func directoryList(path: String) -> some View {
        WorkspaceFilesDirectoryList(
            checkout: checkout, relPath: path,
            onBack: self.path.isEmpty ? nil : { self.path.removeLast() },
            onOpenDirectory: { folder in
                self.path.append(FilePathItem(path: folder))
            },
            onOpenFile: { file in
                openFile = file
            },
            revealTarget: revealTarget,
            onRevealConsumed: { revealTarget = nil })
    }

    /// The folder a file lives in, as the back label; "Files" at the root.
    private func backLabel(for path: String) -> String {
        let containing = WorkspaceFileFormat.containingDirectory(path)
        guard !containing.isEmpty else { return "Files" }
        return WorkspaceFileFormat.lastComponent(containing)
    }
}
#endif
