#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One directory's rows: the back row when nested, then folders first and files after (the store
/// sorts), pull-to-refresh, and calm loading / empty / error states.
struct WorkspaceFilesDirectoryList: View {
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
    /// The row at the top of the list, kept in `WorkspaceFilesLocation` so the folder reopens
    /// scrolled where it was.
    @State private var topRow: String?
    /// A page snapshot: entries, or the error text to show (not `Result`: the failure is plain text).
    private enum Listing: Equatable {
        case success([FileExplorerEntry])
        case failure(String)
    }
    /// Hidden files (dotfiles) are filtered out unless this is on; persisted per device.
    @AppStorage("paseo.files.showHidden") private var showHidden = false
    /// List ordering; folders always come first regardless of key. Persisted per device.
    @AppStorage("paseo.files.sortOrder") private var sort: FileSort = .name
    @State private var namePrompt: NamePrompt?
    @State private var nameText = ""
    @State private var pendingDelete: FileExplorerEntry?
    @State private var sharingPath: String?
    @State private var shareTarget: SharePayload?
    @State private var savingToFilesPath: String?
    @State private var exportDocument: WorkspaceExportDocument?
    @State private var isExporting = false
    @State private var exportType: UTType?
    @State private var exportName: String?
    /// The flash-highlighted row (workspace-relative path), if any; clears after a beat.
    @State private var revealedRow: String?
    @State private var revealHandled: String?
    @State private var listMemo = FileListMemo()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toast) private var toast

    private var files: WorkspaceFiles { checkout.files }

    var body: some View {
        VStack(spacing: 0) {
            header
            ClaudeDivider()
            content
        }
        // Every pushed folder draws its own header row; the system bar would duplicate it.
        .toolbarVisibility(.hidden, for: .navigationBar)
        .paseoFeedback(.selection, trigger: sort)
        // The page owns the canvas too: a NavigationStack's own background must never be what
        // shows in dark or pure black (E2 §5).
        .background(Palette.panel)
        .task { await refresh() }
        .onChange(of: listing) { _, _ in syncReveal() }
        .onChange(of: revealTarget) { _, _ in syncReveal() }
        .alert(namePromptTitle, item: $namePrompt) { prompt in
            TextField(prompt.placeholder, text: $nameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(prompt.actionTitle) { submitNamePrompt(prompt) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareTarget) { target in
            ActivityView(items: [target.url])
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
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
        .onChange(of: isExporting) { _, exporting in
            if !exporting { exportDocument = nil }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            item: $pendingDelete,
            titleVisibility: .visible
        ) { entry in
            Button("Delete", role: .destructive) { Task { await deleteEntry(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
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
            Menu("Sort by", systemImage: "arrow.up.arrow.down") {
                Picker("Sort by", selection: $sort) {
                    ForEach(FileSort.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            }
            .labelStyle(.iconOnly)
            .font(.glyph(.small, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            Menu {
                Button("New file", systemImage: "doc") { promptNewFile(in: relPath) }
                Button("New folder", systemImage: "folder") { promptNewFolder(in: relPath) }
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
            // First listing of this page: come back to the row that was on top last time.
            if listing == nil {
                topRow = WorkspaceFilesLocation.topRow(folder: relPath, in: checkout.workspaceId)
            }
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
            let visible = listMemo.visible(
                entries, showHidden: showHidden, sort: sort
            ) { sortedVisible(entries) }
            if visible.isEmpty {
                emptyView
            } else {
                list(visible)
            }
        }
    }

    private var hiddenCount: Int {
        guard case .success(let entries) = listing else { return 0 }
        return entries.count(where: { $0.name.hasPrefix(".") })
    }

    /// Folders first always, then the chosen key: name (A–Z), modified (newest first), size (largest first).
    private func sortedVisible(_ entries: [FileExplorerEntry]) -> [FileExplorerEntry] {
        let visible = entries.filter { showHidden || !$0.name.hasPrefix(".") }
        let dirs = sortEntries(visible.filter { $0.isDirectory })
        let files = sortEntries(visible.filter { !$0.isDirectory })
        return dirs + files
    }

    private func sortEntries(_ entries: [FileExplorerEntry]) -> [FileExplorerEntry] {
        switch sort {
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
                    // One container per element, so every row has the same shape and the lazy
                    // stack identifies rows by id alone; the first row's divider is hidden, not
                    // left out.
                    ForEach(visible.enumerated(), id: \.element.id) { index, entry in
                        let relativePath = relative(entry)
                        VStack(spacing: 0) {
                            ClaudeDivider()
                                .padding(.leading, 46)
                                .opacity(index > 0 ? 1 : 0)
                            FileEntryRow(
                                entry: entry,
                                relativePath: relativePath,
                                absolutePath: absolute(entry),
                                subtitle: meta(entry),
                                isRevealed: revealedRow == relativePath,
                                isBusy: sharingPath == entry.path || savingToFilesPath == entry.path,
                                onOpen: {
                                    if entry.isDirectory {
                                        onOpenDirectory(entry.path)
                                    } else {
                                        onOpenFile(entry.path)
                                    }
                                },
                                onShare: { share(entry) },
                                onSaveToFiles: { saveToFiles(entry) },
                                onRename: { promptRename(entry) },
                                onDuplicate: { Task { await duplicate(entry) } },
                                onNewFile: { promptNewFile(in: entry.path) },
                                onNewFolder: { promptNewFolder(in: entry.path) },
                                onDelete: { pendingDelete = entry })
                        }
                        .id(relativePath)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topRow, anchor: .top)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: topRow) { _, row in
                WorkspaceFilesLocation.setTopRow(
                    row, folder: relPath, in: checkout.workspaceId)
            }
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
                ? String(
                    AttributedString(
                        localized: "^[\(hiddenCount) hidden item](inflect: true) not shown",
                        bundle: #bundle
                    ).characters)
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

    private func promptNewFile(in parent: String) {
        nameText = ""
        namePrompt = .newFile(parent: parent)
    }

    private func promptNewFolder(in parent: String) {
        nameText = ""
        namePrompt = .newFolder(parent: parent)
    }

    private func promptRename(_ entry: FileExplorerEntry) {
        nameText = entry.name
        namePrompt = .rename(path: entry.path, currentName: entry.name)
    }

    private func submitNamePrompt(_ prompt: NamePrompt) {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                isExporting = true
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
