#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The Files page's file viewer: text with syntax highlighting and a line-number gutter, an image
/// renderer, and calm messages for binary or too-large files. Top row: back to the folder, the
/// file's name, a copy button when there is something to copy.
///
/// Decoding, image downscaling and the line split happen off the main actor into a
/// `FileRenderModel`; nothing decodes in `body`.
struct WorkspaceFileViewer: View {
    let checkout: CheckoutStore
    let relPath: String
    let onBack: () -> Void
    let backLabel: String
    /// "Reveal in Files page"; nil hides the action (e.g. Preview sheets).
    var onReveal: (() -> Void)? = nil

    @Environment(\.workspaceGitExtras) private var gitExtras
    @State private var copied = false
    @State private var isEditing = false
    /// The editor's buffer; only meaningful while `isEditing`.
    @State private var editText = ""
    /// Whether the buffer differs from the file. Written by `FileEditor`, so a keystroke does not
    /// re-evaluate this view.
    @State private var isDirty = false
    @State private var editBaseline = ""
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var showConflict = false
    @State private var conflictModifiedAt = ""
    @State private var savedFlash = false
    @State private var previewAsSource = false
    /// A link tapped inside an HTML preview: opened in an in-app Safari sheet, never in the preview.
    @State private var previewLink: BrowserTarget?
    @State private var shareTarget: SharePayload?
    @State private var isSharing = false
    @State private var shareFailure: String?
    @State private var isPreparingSave = false
    @State private var exportDocument: WorkspaceExportDocument?
    @State private var isExporting = false
    @State private var exportType: UTType?
    @State private var exportName: String?
    @State private var saveSuccessFlash = false
    /// The decoded/highlighted file, built once per path + revision.
    @State private var render: FileRenderModel?
    /// An `.html` file opened full screen on the artifact page (G5 C8).
    @State private var htmlArtifact: ArtifactDocument?
    /// Where the dirty-edit dialog should go if the reader confirms.
    @State private var pendingExit: ExitAction?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    /// The viewer's laid-out size, read once per resize (not per scroll frame). Image decoding
    /// and syntax bounds derive from it; no `UIScreen` lookup.
    @State private var stageSize: CGSize = .zero
    @Namespace private var imageZoom

    private var files: WorkspaceFiles { checkout.files }
    private var fileName: String { WorkspaceFileFormat.lastComponent(relPath) }
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdwn", "mdx"]
    private static let htmlExtensions: Set<String> = ["html", "htm"]

    /// Lowercased extension of the file on screen, from the path the daemon reported.
    private var fileExtension: String? {
        let path = file?.path ?? relPath
        return path.split(separator: ".", omittingEmptySubsequences: true).last.map { $0.lowercased() }
    }

    /// Whether this file renders through the Markdown preview path (text-like only).
    private var isMarkdown: Bool {
        guard let file, file.kind == .text || file.kind == .image else { return false }
        return fileExtension.map(Self.markdownExtensions.contains) ?? false
    }

    /// An HTML page: gets a Preview / Source control, previewed in the sandboxed web view.
    private var isHTML: Bool {
        guard let file, file.kind == .text else { return false }
        return fileExtension.map(Self.htmlExtensions.contains) ?? false
    }

    /// SVG arrives from the daemon as image bytes (it is not a bitmap UIKit can decode), so it
    /// takes the web-view path instead of `UIImage`.
    private var isSVG: Bool { file?.kind == .image && fileExtension == "svg" }

    /// Text files under ~512 KB, when the host allows editing (`features.workspaceFileEditing`).
    private var editableFile: FileExplorerFile? {
        guard files.supportsFileEditing, let file, file.kind == .text,
            file.textContent != nil, file.size <= 512 * 1024
        else { return nil }
        return file
    }
    /// Workspace-relative path for the "Mention in chat" action and the live-file watch.
    private var relativePath: String {
        WorkspaceFileFormat.relativePath(relPath, cwd: checkout.cwd)
    }

    /// The store keeps one file; show it only while it is the file we asked for.
    private var file: FileExplorerFile? {
        guard let file = files.file else { return nil }
        if WorkspaceFileFormat.relativePath(file.path, cwd: checkout.cwd) == relPath { return file }
        if file.path == relPath { return file }
        return nil
    }

    private var renderKey: FileRenderKey? {
        // No budget before the first layout: wait one frame for the real size instead of
        // decoding twice (placeholder first, image at the layout size).
        guard let file, stageSize.width > 1 || stageSize.height > 1 else { return nil }
        return FileRenderKey(
            path: file.path,
            revision: file.revision ?? file.modifiedAt,
            dark: colorScheme == .dark,
            pixelBudget: pixelBudget)
    }

    /// The largest edge this viewer can draw, in pixels; 512 until the first layout pass. Part of
    /// `renderKey`, so a rotation re-decodes once at the new size.
    private var pixelBudget: Int {
        let dimension = max(stageSize.width, stageSize.height)
        guard dimension > 1 else { return 512 }
        return max(Int(dimension * displayScale), 512)
    }

    var body: some View {
        VStack(spacing: 0) {
            FileViewerTopBar(
                fileName: fileName,
                backLabel: backLabel,
                relativePath: relativePath,
                isEditing: isEditing,
                isSaving: isSaving,
                isPreparingSave: isPreparingSave,
                copied: copied,
                showsSaved: savedFlash || saveSuccessFlash,
                canCopy: canCopy,
                canEdit: editableFile != nil,
                onReveal: onReveal,
                onBack: { requestExit(.leave) },
                onCancelEditing: { requestExit(.cancelEditing) },
                onSave: { Task { await saveEdit() } },
                onCopy: copyContents,
                onEdit: beginEdit,
                onShare: shareCurrentFile,
                onSaveToFiles: saveCurrentFile)
            ClaudeDivider()
            if let saveFailure {
                InlineBanner(.failure, title: saveFailure, onDismiss: { self.saveFailure = nil })
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
            }
            if let shareFailure {
                InlineBanner(.failure, title: shareFailure, onDismiss: { self.shareFailure = nil })
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
            }
            if isEditing {
                FileEditor(
                    text: $editText, baseline: editableFile?.textContent ?? "", isDirty: $isDirty)
            } else if isMarkdown || isHTML {
                FilePreviewToggleRow(
                    previewAsSource: $previewAsSource,
                    showsFullScreen: isHTML && !previewAsSource && file?.textContent != nil,
                    onFullScreen: openHTMLArtifact)
                if isMarkdown {
                    FileMarkdownPreview(
                        render: render, previewAsSource: previewAsSource,
                        fileSize: file?.size ?? 0)
                } else {
                    FileHTMLPreview(
                        render: render, previewAsSource: previewAsSource,
                        fileSize: file?.size ?? 0, checkout: checkout, relativePath: relativePath,
                        onExternalNavigation: { url in previewLink = BrowserTarget(url: url) })
                }
            } else {
                content
            }
        }
        // `FileViewerTopBar` is the header (back, title, actions); the system bar would duplicate it.
        .toolbarVisibility(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isDirty)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            stageSize = size
        }
        // A markdown preview can hold images and HTML: cap them against this viewer, not a screen.
        .environment(\.richViewportHeight, stageSize.height > 1 ? stageSize.height : 800)
        .confirmationDialog(
            "Discard changes?",
            item: $pendingExit,
            titleVisibility: .visible
        ) { _ in
            Button("Discard changes", role: .destructive) { performExit() }
            Button("Keep editing", role: .cancel) {}
        }
        .task {
            if let gitExtras { await gitExtras.watchFile(relativePath) }
            guard !Task.isCancelled else { return }
            await files.read(relativePath)
        }
        // The daemon pushed a new version: re-read, keeping the scroll position (the code
        // view's identity is stable across re-reads, so the offset survives).
        .onChange(of: gitExtras?.watchedFile) { _, version in
            guard version != nil else { return }
            Task { await files.read(relativePath) }
        }
        .onDisappear {
            guard let gitExtras else { return }
            Task { await gitExtras.stopWatchingFile() }
        }
        .task(id: renderKey) {
            await buildRender()
        }
        .sheet(item: $shareTarget) { target in
            ActivityView(items: [target.url])
        }
        .sheet(item: $previewLink) { target in
            SafariView(url: target.url).ignoresSafeArea()
        }
        .fullScreenCover(item: $htmlArtifact) { document in
            ArtifactPage(
                document: document,
                sourceID: document.id,
                namespace: imageZoom,
                previewFiles: PreviewFileSource(files: files, workspaceId: checkout.workspaceId),
                onClose: { htmlArtifact = nil })
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
                saveSuccessFlash = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    saveSuccessFlash = false
                }
            case .failure(let error):
                guard !WorkspaceShare.isUserCancellation(error) else { return }
                Haptics.failure()
                shareFailure = "Couldn't save the file."
            }
        }
        .onChange(of: isExporting) { _, exporting in
            if !exporting { exportDocument = nil }
        }
        .alert("Changed on disk", isPresented: $showConflict) {
            Button("Reload") { Task { await reloadForConflict() } }
            Button("Overwrite", role: .destructive) { Task { await overwriteForConflict() } }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This file changed on disk since you started editing. Reloading discards your changes.")
        }
        .paseoFeedback(.success, trigger: saveSuccessFlash) { _, new in new }
        .paseoFeedback(.success, trigger: savedFlash) { _, new in new }
        .paseoFeedback(.light, trigger: copied) { _, new in new }
        .paseoFeedback(.selection, trigger: previewAsSource)
    }

    // MARK: Render

    private func buildRender() async {
        guard let file else {
            render = nil
            return
        }
        // Before the first layout there is no pixel budget: `.task(id:)` fires again once
        // `renderKey` gains one, so this returns instead of decoding twice.
        guard let key = renderKey else { return }
        let language = language(for: file.path)
        let theme: ClaudeCodeSyntaxTheme = colorScheme == .dark ? .dark : .light
        let maxPixel = max(key.pixelBudget, 512)
        let model = await FileRenderModel.make(
            file: file, language: language, theme: theme, maxPixel: maxPixel)
        guard !Task.isCancelled, renderKey == key else { return }
        render = model
    }

    // MARK: Editing

    private func beginEdit() {
        guard let file = editableFile else { return }
        editText = file.textContent ?? ""
        isDirty = false
        editBaseline = file.modifiedAt
        saveFailure = nil
        isEditing = true
    }

    private func cancelEdit() {
        editText = ""
        isDirty = false
        saveFailure = nil
        isEditing = false
    }

    /// Back or Cancel while the buffer has unsaved edits asks first.
    private func requestExit(_ action: ExitAction) {
        if isDirty {
            pendingExit = action
        } else {
            pendingExit = action
            performExit()
        }
    }

    private func performExit() {
        guard let action = pendingExit else { return }
        pendingExit = nil
        switch action {
        case .leave:
            cancelEdit()
            onBack()
        case .cancelEditing:
            cancelEdit()
        }
    }

    private func saveEdit() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let outcome = await files.write(path: relativePath, content: editText, expectedModifiedAt: editBaseline)
        await applyWriteOutcome(outcome)
    }

    private func applyWriteOutcome(_ outcome: FileWriteOutcome) async {
        switch outcome {
        case .written:
            isEditing = false
            editText = ""
            isDirty = false
            saveFailure = nil
            savedFlash = true
            await files.read(relativePath)
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                savedFlash = false
            }
        case .conflict(let modifiedAt):
            if let modifiedAt, !modifiedAt.isEmpty {
                conflictModifiedAt = modifiedAt
            } else {
                // The daemon reported a conflict without a version. Overwrite needs a real
                // expectation (the wire forbids blind writes), so re-read to learn the
                // current version before asking. If that still yields nothing, Overwrite
                // explains instead of looping back into another conflict.
                await files.read(relativePath)
                conflictModifiedAt = files.file?.modifiedAt ?? ""
            }
            showConflict = true
        case .failed(let message):
            saveFailure = message
        }
    }

    /// The user chose Reload: throw away their edits and read the on-disk version.
    private func reloadForConflict() async {
        await files.read(relativePath)
        guard let file = files.file, file.kind == .text, let text = file.textContent else {
            saveFailure = files.error ?? "The file could not be reloaded."
            return
        }
        editText = text
        isDirty = false
        editBaseline = file.modifiedAt
        saveFailure = nil
    }

    /// The user chose Overwrite: save with the current on-disk version as the expectation.
    private func overwriteForConflict() async {
        guard !conflictModifiedAt.isEmpty else {
            saveFailure = "The host didn't report the file's current version. Reload to see the latest, then re-apply your edits."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let outcome = await files.write(path: relativePath, content: editText, expectedModifiedAt: conflictModifiedAt)
        await applyWriteOutcome(outcome)
    }

    /// Whether the decoded model has anything to copy.
    private var canCopy: Bool {
        guard let render else { return false }
        switch render.payload {
        case .text(let text, _, _): return !text.isEmpty
        case .image(let data, _): return !data.isEmpty
        case .svg(let source): return !source.isEmpty
        case .binary: return false
        }
    }

    /// Copy reads the decoded model, never the daemon payload.
    private func copyContents() {
        if let render {
            switch render.payload {
            case .image(_, let image):
                UIPasteboard.general.image = image
            case .text(let text, _, _):
                Clipboard.copy(text)
            case .svg(let source):
                Clipboard.copy(source)
            case .binary:
                break
            }
        }
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let file {
            switch file.kind {
            case .image:
                if isSVG {
                    FileSVGPreview(render: render)
                } else {
                    FileImagePreview(
                        render: render, relPath: relPath, fileName: fileName, namespace: imageZoom)
                }
            case .binary:
                FileUnsupportedShareView(
                    icon: "doc", title: "Binary file",
                    detail: "\(WorkspaceFileFormat.bytes(file.size)) · \(WorkspaceFileFormat.relativeModified(file.modifiedAt))",
                    isSharing: isSharing, onShare: shareCurrentFile)
            default:
                textView
            }
        } else if case .failed(let message) = files.phase {
            EmptyState(
                systemImage: "exclamationmark.triangle", title: message,
                action: (title: "Try again", run: { Task { await files.read(relativePath) } }))
                .padding(.horizontal, Space.xxxl)
        } else {
            LoadingState()
        }
    }

    @ViewBuilder private var textView: some View {
        if let render, case .text(let text, let highlighted, let lines) = render.payload {
            WorkspaceCodeView(text: text, highlighted: highlighted, lines: lines).equatable()
        } else if render == nil {
            LoadingState()
        } else {
            EmptyState(
                systemImage: "doc.text", title: "No content",
                message: "The host returned no text for this file.")
                .padding(.horizontal, Space.xxxl)
        }
    }

    /// An `.html` file on the artifact page: the live document with workspace file
    /// access, Reload and Share as .html (G5 C8). Inline stays the preview.
    private func openHTMLArtifact() {
        guard let file, let text = file.textContent else { return }
        Haptics.light()
        htmlArtifact = ArtifactDocument(
            kind: .html(source: text, fileName: fileName),
            shareImage: nil)
    }

    /// Reads the bytes into memory and presents `fileExporter` (socket read via WorkspaceShare;
    /// the HTTP token route is unreachable from this client).
    private func saveCurrentFile() {
        guard !isPreparingSave, let file else { return }
        isPreparingSave = true
        shareFailure = nil
        Task {
            do {
                let name = file.path.split(separator: "/").last.map(String.init)
                let payload = try await WorkspaceShare.prepareExport(
                    checkout, path: relativePath, name: name)
                exportName = payload.displayName
                exportType = payload.contentType
                exportDocument = WorkspaceExportDocument(data: payload.data)
                isExporting = true
            } catch let error as WorkspaceShare.ShareError {
                if case .unreadable(let message) = error { shareFailure = message }
            } catch {
                shareFailure = "Couldn't prepare the file."
            }
            isPreparingSave = false
        }
    }

    private func shareCurrentFile() {
        guard !isSharing, let file else { return }
        isSharing = true
        shareFailure = nil
        Task {
            do {
                let name = file.path.split(separator: "/").last.map(String.init)
                let url = try await WorkspaceShare.prepare(checkout, path: relativePath, name: name)
                shareTarget = SharePayload(url: url, name: name ?? "file")
            } catch let error as WorkspaceShare.ShareError {
                if case .unreadable(let message) = error { shareFailure = message }
            } catch {
                shareFailure = "Couldn't prepare the file for sharing."
            }
            isSharing = false
        }
    }

    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
    }

    private func language(for path: String) -> String? {
        let ext = path.split(separator: ".", omittingEmptySubsequences: true).last.map { $0.lowercased() }
        guard let ext, !ext.isEmpty else { return nil }
        return ext
    }
}
extension String {
    /// The file viewer's line split: keep empty lines and a trailing empty line.
    func splitLines() -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
#endif
