#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// A folder pushed onto the Files navigation stack.
struct FilePathItem: Hashable {
    let path: String
}

/// The "Files" page of the workspace panel (`WorkspacePanel`): a real navigation stack of
/// folders, so the system back button and the edge swipe pop one level at a time.
struct WorkspaceFilesView: View {
    let checkout: CheckoutStore

    @State private var path: [FilePathItem] = []
    /// The file pushed on top of the folder stack.
    @State private var openFile: String?
    /// Workspace-relative path of a file the Files page should flash and scroll to
    /// ("Reveal in Files page" from the viewer); consumed by the containing directory page.
    @State private var revealTarget: String?
    @Environment(\.shellDrawer) private var shellDrawer

    private var files: WorkspaceFiles { checkout.files }

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
                .toolbar(.hidden, for: .navigationBar)
        }
        // The Files page and every pushed folder/file share the panel canvas (E2 §5): without
        // this the window's black shows through in dark and pure black.
        .background(Palette.panel)
        .onAppear { shellDrawer?.panelHandlesBack = !path.isEmpty }
        .onChange(of: path) { _, newPath in
            shellDrawer?.panelHandlesBack = !newPath.isEmpty
        }
        .onChange(of: openFile) { _, _ in
            // A file is a terminal destination; only folders make the stack "deeper".
            shellDrawer?.panelHandlesBack = !path.isEmpty
        }
        .onDisappear { shellDrawer?.panelHandlesBack = false }
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

/// One generation counter shared by the Files pages: only the newest refresh's result is
/// trusted, so two pages can never render each other's listing. All Files state lives on the
/// main actor.
@MainActor private enum WorkspaceFilesRefresh {
    static var generation = 0
}

/// The list ordering keys. Folders always come first regardless of key.
private enum FileSort: String, CaseIterable {
    case name, modified, size

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Modified"
        case .size: "Size"
        }
    }
}

/// One directory's rows: the back row when nested, then folders first and files after (the store
/// sorts), pull-to-refresh, and calm loading / empty / error states.
private struct WorkspaceFilesDirectoryList: View {
    let checkout: CheckoutStore
    let relPath: String
    let onBack: (() -> Void)?
    let onOpenDirectory: (String) -> Void
    let onOpenFile: (String) -> Void
    /// Workspace-relative path to flash and scroll to, if any ("Reveal in Files page").
    var revealTarget: String?
    /// Called once the containing page has consumed `revealTarget` (or timed out).
    var onRevealConsumed: () -> Void = {}

    /// The listing of this page's directory, captured when this page's refresh completed. The
    /// store keeps a single listing, so pages snapshot it rather than watch it change.
    @State private var listing: Listing?
    /// A page snapshot: entries, or the error text to show (not `Result`: the failure is plain text).
    private enum Listing: Equatable {
        case success([FileExplorerEntry])
        case failure(String)
    }
    /// Hidden files (dotfiles) are filtered out unless this is on; persisted per device.
    @AppStorage("paseo.files.showHidden") private var showHidden = false
    /// List ordering; folders always come first regardless of key. Persisted per device.
    @AppStorage("paseo.files.sortOrder") private var sortRaw = "name"
    @State private var namePrompt: NamePrompt?
    @State private var nameText = ""
    @State private var pendingDelete: FileExplorerEntry?
    @State private var sharingPath: String?
    @State private var shareTarget: SharePayload?
    @State private var savingToFilesPath: String?
    @State private var exportDocument: WorkspaceExportDocument?
    @State private var exportType: UTType?
    @State private var exportName: String?
    /// The flash-highlighted row (workspace-relative path), if any; clears after a beat.
    @State private var revealedRow: String?
    @State private var revealHandled: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toast) private var toast
    /// "Mention in chat" from a row's long-press; nil disables the action.
    @Environment(\.mentionInChat) private var mentionInChat

    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeDivider()
            content
        }
        // Every pushed folder draws its own header row; the system bar would duplicate it.
        .toolbar(.hidden, for: .navigationBar)
        // The page owns the canvas too: a NavigationStack's own background must never be what
        // shows in dark or pure black (E2 §5).
        .background(Palette.panel)
        .task { await refresh() }
        .onChange(of: listing) { _, _ in syncReveal() }
        .onChange(of: revealTarget) { _, _ in syncReveal() }
        .alert(namePromptTitle, isPresented: namePromptBinding) {
            TextField(namePromptPlaceholder, text: $nameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(namePromptAction, action: submitNamePrompt)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareTarget) { target in
            ActivityView(items: [target.url])
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }),
            document: exportDocument ?? WorkspaceExportDocument(data: Data()),
            contentType: exportType ?? .data,
            defaultFilename: exportName
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                Haptics.success()
                toast?.show("Saved to Files")
            case .failure(let error):
                guard !WorkspaceShare.isUserCancellation(error) else { return }
                Haptics.failure()
                toast?.show("Couldn't save: \(error.localizedDescription)")
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let target = pendingDelete else { return }
                pendingDelete = nil
                Task { await deleteEntry(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes it. This cannot be undone.")
        }
    }

    // MARK: Header row

    private var header: some View {
        HStack(spacing: Space.sm) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "chevron.left").font(.glyph(.small, weight: .semibold))
                        Text(backTitle)
                            .font(.paseo(.footnote))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityLabel("Back to \(backTitle)")
            }
            // At the root the segmented control already says "Files": no second static label
            // here, and the actions stay trailing-aligned (E2b §12). A subfolder shows its back
            // folder, one line, truncated in the middle.
            Spacer(minLength: Space.sm)
            Menu {
                ForEach(FileSort.allCases, id: \.self) { choice in
                    Button {
                        sortRaw = choice.rawValue
                        Haptics.selection()
                    } label: {
                        if currentSort == choice {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Sort by")
            Menu {
                Button("New file", systemImage: "doc") {
                    nameText = ""
                    namePrompt = .newFile(parent: relPath)
                }
                Button("New folder", systemImage: "folder") {
                    nameText = ""
                    namePrompt = .newFolder(parent: relPath)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("New file or folder")
            Menu {
                Toggle("Show hidden files", isOn: $showHidden).tint(Palette.toggleTint)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More file actions")
        }
        .padding(.horizontal, Space.sm)
        .frame(minHeight: 48)
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
            LoadingState()
        case .failure(let message):
            InlineBanner(
                .failure, title: message,
                action: ("Try again", { Task { await refresh() } })
            )
            .padding(.horizontal, Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .success(let entries):
            let visible = sortedVisible(entries)
            if visible.isEmpty {
                emptyView
            } else {
                list(visible)
            }
        }
    }

    private var hiddenCount: Int {
        guard case .success(let entries) = listing else { return 0 }
        return entries.filter { $0.name.hasPrefix(".") }.count
    }

    private var currentSort: FileSort { FileSort(rawValue: sortRaw) ?? .name }

    /// Folders first always, then the chosen key: name (A–Z), modified (newest first), size (largest first).
    private func sortedVisible(_ entries: [FileExplorerEntry]) -> [FileExplorerEntry] {
        let visible = entries.filter { showHidden || !$0.name.hasPrefix(".") }
        let dirs = sortEntries(visible.filter { $0.isDirectory })
        let files = sortEntries(visible.filter { !$0.isDirectory })
        return dirs + files
    }

    private func sortEntries(_ entries: [FileExplorerEntry]) -> [FileExplorerEntry] {
        switch currentSort {
        case .name:
            return entries.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .modified:
            return entries.sorted {
                (PaseoDate.parse($0.modifiedAt) ?? .distantPast)
                    > (PaseoDate.parse($1.modifiedAt) ?? .distantPast)
            }
        case .size:
            return entries.sorted { $0.size > $1.size }
        }
    }

    private func list(_ visible: [FileExplorerEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            ClaudeDivider().padding(.leading, 46)
                        }
                        row(entry)
                            .id(relative(entry))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await refresh() }
            .onChange(of: revealedRow) { _, target in
                guard let target else { return }
                if reduceMotion {
                    proxy.scrollTo(target, anchor: .center)
                } else {
                    withAnimation(Motion.disclosure.animation) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    private func row(_ entry: FileExplorerEntry) -> some View {
        let revealed = revealedRow == relative(entry)
        return ListRow(
            title: entry.name,
            subtitle: meta(entry),
            systemImage: entry.isDirectory ? "folder" : "doc",
            accessory: accessory(entry),
            action: {
                if entry.isDirectory { onOpenDirectory(entry.path) } else { onOpenFile(entry.path) }
            }
        )
        .background(revealed ? Palette.chip.opacity(0.9) : Color.clear)
        .draggable(relative(entry))
        .contextMenu {
            if !entry.isDirectory {
                Button("Add to chat", systemImage: "at") {
                    mentionInChat?(relative(entry))
                }
            }
            Button("Share…", systemImage: "square.and.arrow.up") {
                share(entry)
            }
            Button("Save to Files…", systemImage: "square.and.arrow.down") {
                saveToFiles(entry)
            }
            Button("Rename…", systemImage: "pencil") {
                nameText = entry.name
                namePrompt = .rename(path: entry.path, currentName: entry.name)
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await duplicate(entry) }
            }
            if entry.isDirectory {
                Button("New file", systemImage: "doc") {
                    nameText = ""
                    namePrompt = .newFile(parent: entry.path)
                }
                Button("New folder", systemImage: "folder") {
                    nameText = ""
                    namePrompt = .newFolder(parent: entry.path)
                }
            }
            Button("Delete…", systemImage: "trash", role: .destructive) {
                pendingDelete = entry
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                Clipboard.copy(absolute(entry), toast: toast)
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                Clipboard.copy(relative(entry), toast: toast)
            }
        }
    }

    private func accessory(_ entry: FileExplorerEntry) -> ListRow.Accessory {
        if sharingPath == entry.path || savingToFilesPath == entry.path { return .progress }
        return entry.isDirectory ? .chevron : .none
    }

    private var emptyView: some View {
        let allHidden = !showHidden && hiddenCount > 0
        let action: (title: String, run: () -> Void)? = allHidden
            ? (title: "Show hidden files", run: {
                Haptics.selection()
                showHidden = true
            })
            : nil
        return EmptyState(
            systemImage: "folder",
            title: allHidden ? "No visible files" : "Empty folder",
            message: allHidden
                ? "\(PaseoFormat.integer(hiddenCount)) hidden \(hiddenCount == 1 ? "item is" : "items are") dot-prefixed."
                : "There is nothing to show here yet.",
            action: action)
        .padding(.horizontal, Space.xl)
    }

    // MARK: Entry operations

    private enum NamePrompt: Identifiable {
        case newFile(parent: String)
        case newFolder(parent: String)
        case rename(path: String, currentName: String)

        var id: String {
            switch self {
            case .newFile(let parent): "new-file:\(parent)"
            case .newFolder(let parent): "new-folder:\(parent)"
            case .rename(let path, _): "rename:\(path)"
            }
        }

        var title: String {
            switch self {
            case .newFile: "New file"
            case .newFolder: "New folder"
            case .rename: "Rename"
            }
        }

        var actionTitle: String {
            switch self {
            case .newFile: "Create"
            case .newFolder: "Create"
            case .rename: "Rename"
            }
        }

        var placeholder: String {
            switch self {
            case .newFile: "File name"
            case .newFolder: "Folder name"
            case .rename: "Name"
            }
        }
    }

    private var namePromptTitle: String { namePrompt?.title ?? "" }
    private var namePromptAction: String { namePrompt?.actionTitle ?? "OK" }
    private var namePromptPlaceholder: String { namePrompt?.placeholder ?? "Name" }

    private var namePromptBinding: Binding<Bool> {
        Binding(
            get: { namePrompt != nil },
            set: { if !$0 { namePrompt = nil } })
    }

    private func submitNamePrompt() {
        guard let prompt = namePrompt else { return }
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        namePrompt = nil
        guard !name.isEmpty else { return }
        Haptics.light()
        Task {
            switch prompt {
            case .newFile(let parent):
                let created = await files.createEntry(
                    parentPath: parent.isEmpty ? nil : parent, name: name, kind: .file)
                showToast(created != nil ? "Created \(name)" : (files.error ?? "Couldn't create the file."))
            case .newFolder(let parent):
                let created = await files.createEntry(
                    parentPath: parent.isEmpty ? nil : parent, name: name, kind: .directory)
                showToast(created != nil ? "Created \(name)" : (files.error ?? "Couldn't create the folder."))
            case .rename(let path, _):
                let renamed = await files.rename(path: path, to: name)
                showToast(renamed != nil ? "Renamed" : (files.error ?? "Couldn't rename."))
            }
            await refresh()
        }
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
    }

    /// Reads the bytes through the files store, writes to a temp file, hands the URL to the
    /// share sheet. The read RPC does not stream, so the row shows an indeterminate spinner.
    private func share(_ entry: FileExplorerEntry) {
        guard sharingPath == nil else { return }
        sharingPath = entry.path
        Task {
            do {
                let url = try await WorkspaceShare.prepare(
                    checkout, path: relative(entry), name: entry.name)
                shareTarget = SharePayload(url: url, name: entry.name)
            } catch let error as WorkspaceShare.ShareError {
                if case .unreadable(let message) = error { showToast(message) }
            } catch {
                showToast("Couldn't prepare the file for sharing.")
            }
            sharingPath = nil
        }
    }

    /// Reads the bytes through the files store into memory and presents `fileExporter`.
    /// Same read path as share; no HTTP token route on this client (see WorkspaceShare).
    private func saveToFiles(_ entry: FileExplorerEntry) {
        guard savingToFilesPath == nil else { return }
        savingToFilesPath = entry.path
        Task {
            do {
                let payload = try await WorkspaceShare.prepareExport(
                    checkout, path: relative(entry), name: entry.name)
                exportName = payload.displayName
                exportType = payload.contentType
                exportDocument = WorkspaceExportDocument(data: payload.data)
            } catch let error as WorkspaceShare.ShareError {
                if case .unreadable(let message) = error { showToast(message) }
            } catch {
                showToast("Couldn't prepare the file.")
            }
            savingToFilesPath = nil
        }
    }

    /// Fires only in the page that actually holds the row: flash it, scroll to it, then clear.
    private func syncReveal() {
        guard let target = revealTarget, revealHandled != target else { return }
        guard case .success(let entries) = listing,
            entries.contains(where: { relative($0) == target })
        else { return }
        revealHandled = target
        revealedRow = target
        Task {
            try? await Task.sleep(for: .seconds(3))
            if revealedRow == revealTarget { revealedRow = nil }
            onRevealConsumed()
        }
    }

    private func duplicate(_ entry: FileExplorerEntry) async {
        Haptics.light()
        let duplicated = await files.duplicate(path: entry.path)
        if duplicated != nil {
            showToast("Duplicated \(entry.name)")
        } else {
            showToast(files.error ?? "Couldn't duplicate.")
        }
        await refresh()
    }

    private func deleteEntry(_ entry: FileExplorerEntry) async {
        let ok = await files.delete(path: entry.path)
        if ok {
            Haptics.light()
            showToast("Deleted \(entry.name)")
        } else {
            showToast(files.error ?? "Couldn't delete.")
        }
        await refresh()
    }

    private func showToast(_ text: String) {
        toast?.show(text)
    }

    // MARK: Path helpers

    private func relative(_ entry: FileExplorerEntry) -> String {
        WorkspaceFileFormat.relativePath(entry.path, cwd: checkout.cwd)
    }

    private func absolute(_ entry: FileExplorerEntry) -> String {
        entry.path.hasPrefix("/") ? entry.path : checkout.cwd + "/" + relative(entry)
    }

    private func meta(_ entry: FileExplorerEntry) -> String? {
        // The daemon sends the directory inode size for folders, not their contents
        // (FileExplorerEntrySchema `size`, messages.ts:2937-2943; fs.stat in the daemon).
        // Folders show only the modified time (UX-SPEC §6).
        WorkspaceFileFormat.metaLine(size: entry.isDirectory ? 0 : entry.size, modifiedAt: entry.modifiedAt)
    }
}
#endif
