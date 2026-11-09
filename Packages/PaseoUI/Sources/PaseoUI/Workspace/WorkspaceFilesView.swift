#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Contract for ticket M3b: the "Files" page of the workspace panel (`WorkspacePanel`).
/// The panel constructs it with exactly these properties; M3b replaces the body.
struct WorkspaceFilesView: View {
    let checkout: CheckoutStore

    @State private var stack: [WorkspaceFilesRoute] = []
    /// Workspace-relative path of a file the Files page should flash and scroll to
    /// ("Reveal in Files page" from the viewer); consumed by the containing directory page.
    @State private var revealTarget: String?
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
                backLabel: backLabel(for: path), onReveal: { reveal(relPath: path) })
            .id(path)
        }
    }

    /// Pop the file's routes off the stack; the containing directory page stays (or, for a
    /// root-level file, the root list). The page consumes `revealTarget` to flash the row.
    private func reveal(relPath: String) {
        stack.removeAll { route in
            if case .file = route { return true }
            return false
        }
        revealTarget = relPath
        Haptics.selection()
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
            },
            revealTarget: revealTarget,
            onRevealConsumed: { revealTarget = nil })
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
/// sorts), pull-to-refresh, and a calm error with Retry when the read fails.
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
    @State private var listing: Result<[FileExplorerEntry], String>?
    @State private var toast: String?
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
        .onChange(of: listing) { _, _ in syncReveal() }
        .onChange(of: revealTarget) { _, _ in syncReveal() }
        .overlay(alignment: .bottom) { toastView }
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
                showToast("Saved to Files")
            case .failure(let error):
                guard !WorkspaceShare.isUserCancellation(error) else { return }
                Haptics.failure()
                showToast("Couldn't save: \(error.localizedDescription)")
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 34, height: 34)
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
            }
            .accessibilityLabel("New file or folder")
            Menu {
                Toggle("Show hidden files", isOn: $showHidden)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 34, height: 34)
                    .background(ClaudePalette.chip, in: .circle)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More file actions")
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
            let visible = sortedVisible(entries)
            if visible.isEmpty { emptyView } else { list(visible) }
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
        return ScrollViewReader { proxy in
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
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
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
                if sharingPath == entry.path || savingToFilesPath == entry.path {
                    ProgressView().controlSize(.small)
                } else if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(.rect)
            .background(revealedRow == relative(entry) ? ClaudePalette.chip.opacity(0.9) : Color.clear)
        }
        .buttonStyle(.plain)
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
                UIPasteboard.general.string = absolute(entry)
                showToast("Path copied")
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = relative(entry)
                showToast("Relative path copied")
            }
        }
        .accessibilityLabel(rowAccessibilityLabel(entry))
    }

    private func rowAccessibilityLabel(_ entry: FileExplorerEntry) -> String {
        let kind = entry.isDirectory ? "Folder" : "File"
        guard let meta = meta(entry) else { return "\(kind) \(entry.name)" }
        return "\(kind) \(entry.name), \(meta)"
    }

    private var emptyView: some View {
        let allHidden = !showHidden && hiddenCount > 0
        return VStack(spacing: 10) {
            Text(allHidden ? "No visible files" : "Empty folder")
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text(allHidden
                 ? "\(hiddenCount) hidden \(hiddenCount == 1 ? "item is" : "items are") dot-prefixed."
                 : "There is nothing to show here yet.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
            if allHidden {
                Button {
                    Haptics.selection()
                    showHidden = true
                } label: {
                    Text("Show hidden files")
                        .font(typography.sans(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                        .background(ClaudePalette.chip, in: .capsule)
                }
                .buttonStyle(.plain)
            }
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
        Haptics.selection()
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
        Haptics.selection()
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
        Haptics.selection()
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
        Haptics.selection()
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
            Haptics.selection()
            showToast("Deleted \(entry.name)")
        } else {
            showToast(files.error ?? "Couldn't delete.")
        }
        await refresh()
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
