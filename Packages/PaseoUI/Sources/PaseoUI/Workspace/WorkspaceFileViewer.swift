#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The Files page's file viewer: text with syntax highlighting and a line-number gutter, an image
/// renderer, and calm messages for binary or too-large files. Top row: back to the folder, the
/// file's name, a copy button when there is something to copy.
struct WorkspaceFileViewer: View {
    let checkout: CheckoutStore
    let relPath: String
    let onBack: () -> Void
    let backLabel: String
    /// "Reveal in Files page"; nil hides the action (e.g. Preview sheets).
    var onReveal: (() -> Void)? = nil

    @Environment(\.mentionInChat) private var mentionInChat
    @Environment(\.workspaceGitExtras) private var gitExtras
    @State private var copied = false
    @State private var isEditing = false
    @State private var editText: String?
    @State private var editBaseline = ""
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var showConflict = false
    @State private var conflictModifiedAt = ""
    @State private var savedFlash = false
    @State private var previewAsSource = false
    @State private var shareTarget: SharePayload?
    @State private var isSharing = false
    @State private var shareFailure: String?
    @State private var isPreparingSave = false
    @State private var exportDocument: WorkspaceExportDocument?
    @State private var exportType: UTType?
    @State private var exportName: String?
    @State private var saveSuccessFlash = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        VStack(spacing: 0) {
            topRow
            ClaudeDivider()
            if let saveFailure {
                saveFailureBanner(saveFailure)
            }
            if let shareFailure {
                saveFailureBanner(shareFailure)
            }
            if isEditing {
                editingContent
            } else if isMarkdown || isHTML {
                previewToggleRow
                if isMarkdown { markdownContent } else { htmlContent }
            } else {
                content
            }
        }
        .onAppear {
            Task {
                if let gitExtras { await gitExtras.watchFile(relativePath) }
                await files.read(relativePath)
            }
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
                saveSuccessFlash = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    saveSuccessFlash = false
                }
            case .failure(let error):
                guard !WorkspaceShare.isUserCancellation(error) else { return }
                Haptics.failure()
                shareFailure = "Couldn't save: \(error.localizedDescription)"
            }
        }
        .alert("Changed on disk", isPresented: $showConflict) {
            Button("Reload") { Task { await reloadForConflict() } }
            Button("Overwrite", role: .destructive) { Task { await overwriteForConflict() } }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This file changed on disk since you started editing. Reloading discards your changes.")
        }
    }

    // MARK: Editing

    /// A plain monospaced TextEditor, deliberately without syntax highlighting.
    @ViewBuilder private var editingContent: some View {
        TextEditor(text: Binding(get: { editText ?? "" }, set: { editText = $0 }))
            .font(.paseo(.codeSmall))
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.codeSurface)
            .accessibilityLabel("Edit file contents")
    }

    private func saveFailureBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.failureInk)
            Text(message)
                .font(.paseo(.caption))
                .foregroundStyle(Palette.failureInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                saveFailure = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.failureInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.failureInk.opacity(0.08))
    }

    private func beginEdit() {
        guard let file = editableFile else { return }
        editText = file.textContent
        editBaseline = file.modifiedAt
        saveFailure = nil
        isEditing = true
    }

    private func cancelEdit() {
        editText = nil
        saveFailure = nil
        isEditing = false
    }

    private func saveEdit() async {
        guard let text = editText, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let outcome = await files.write(path: relativePath, content: text, expectedModifiedAt: editBaseline)
        await applyWriteOutcome(outcome)
    }

    private func applyWriteOutcome(_ outcome: FileWriteOutcome) async {
        switch outcome {
        case .written:
            isEditing = false
            editText = nil
            saveFailure = nil
            savedFlash = true
            await files.read(relativePath)
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                savedFlash = false
            }
        case .conflict(let modifiedAt):
            conflictModifiedAt = modifiedAt ?? ""
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
        editBaseline = file.modifiedAt
        saveFailure = nil
    }

    /// The user chose Overwrite: save with the current on-disk version as the expectation.
    private func overwriteForConflict() async {
        guard let text = editText, !conflictModifiedAt.isEmpty else {
            await saveEdit()
            return
        }
        isSaving = true
        defer { isSaving = false }
        let outcome = await files.write(path: relativePath, content: text, expectedModifiedAt: conflictModifiedAt)
        await applyWriteOutcome(outcome)
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.selection()
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.glyph(.small, weight: .semibold))
                    Text(backLabel).font(.paseo(.footnote)).lineLimit(1)
                }
                .foregroundStyle(Palette.secondaryInk)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .accessibilityLabel("Back to \(backLabel)")
            Spacer(minLength: 4)
            Text(isEditing ? "Editing \(fileName)" : fileName)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isEditing {
                Button("Cancel") { cancelEdit() }
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minHeight: 28)
                    .accessibilityLabel("Discard edits")
                Button {
                    Haptics.selection()
                    Task { await saveEdit() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).frame(width: 40, height: 28)
                    } else {
                        Text("Save")
                            .font(.paseo(.footnote, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(minHeight: 28)
                    }
                }
                .disabled(isSaving)
                .accessibilityLabel("Save file")
            } else {
                if let mentionInChat {
                    Button {
                        mentionInChat(relativePath)
                    } label: {
                        Image(systemName: "at")
                            .font(.glyph(.regular, weight: .light))
                            .foregroundStyle(Palette.tertiaryInk)
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention in chat")
                }
                if savedFlash || saveSuccessFlash {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.successInk)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Saved")
                } else if canCopy {
                    copyButton
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
                if editableFile != nil { editButton } else { Color.clear.frame(width: 28, height: 28) }
                overflowMenu
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var overflowMenu: some View {
        Menu {
            if let onReveal {
                Button("Reveal in Files page", systemImage: "folder") {
                    Haptics.selection()
                    onReveal()
                }
            }
            Button("Share…", systemImage: "square.and.arrow.up") { shareCurrentFile() }
            Button("Save to Files…", systemImage: "square.and.arrow.down") { saveCurrentFile() }
        } label: {
            Group {
                if isPreparingSave {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.glyph(.regular, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More file actions")
    }

    private var editButton: some View {
        Button {
            Haptics.selection()
            beginEdit()
        } label: {
            Image(systemName: "pencil")
                .font(.glyph(.regular, weight: .regular))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit file")
    }

    private var canCopy: Bool {
        guard let file else { return false }
        switch file.kind {
        case .image, .binary: return imageData != nil
        default: return file.textContent != nil
        }
    }

    private var imageData: Data? {
        guard let file, file.encoding == .base64, let content = file.content else { return nil }
        return Data(base64Encoded: content, options: .ignoreUnknownCharacters)
    }

    private var copyButton: some View {
        Button {
            Haptics.selection()
            if let data = imageData, let uiImage = UIImage(data: data) {
                UIPasteboard.general.image = uiImage
            } else if let text = file?.textContent {
                UIPasteboard.general.string = text
            }
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(copied ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy file contents")
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let file {
            switch file.kind {
            case .image:
                if isSVG { svgContent(file) } else { zoomableImage(file) }
            case .binary:
                unsupportedShareableView(
                    icon: "doc", title: "Binary file",
                    detail: "\(WorkspaceFileFormat.bytes(file.size)) · \(WorkspaceFileFormat.relativeModified(file.modifiedAt))")
            default:
                textView(file)
            }
        } else if case .failed(let message) = files.phase {
            errorView(message)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func textView(_ file: FileExplorerFile) -> some View {
        if let text = file.textContent {
            if text.utf16.count > 100_000 {
                unsupportedView(
                    icon: "doc.text", title: "File too large to show",
                    detail: "\(WorkspaceFileFormat.bytes(file.size)) · Open it in your editor instead.")
            } else {
                WorkspaceCodeView(source: text, language: language(for: file.path))
            }
        } else {
            unsupportedView(
                icon: "doc.text", title: "No content",
                detail: "The daemon returned no text for this file.")
        }
    }

    private var previewToggleRow: some View {
        HStack {
            HStack(spacing: 2) {
                previewSegment(false, label: "Preview")
                previewSegment(true, label: "Source")
            }
            .padding(2)
            .background(Palette.chip, in: .capsule)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.background)
    }

    private func previewSegment(_ source: Bool, label: String) -> some View {
        let selected = previewAsSource == source
        return Button {
            Haptics.selection()
            if reduceMotion {
                previewAsSource = source
            } else {
                withAnimation(Motion.disclosure.animation) { previewAsSource = source }
            }
        } label: {
            Text(label)
                .font(.paseo(.caption, weight: .medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .foregroundStyle(selected ? Palette.ink : Palette.secondaryInk)
                .background(selected ? Palette.background : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var markdownContent: some View {
        if let text = file?.textContent {
            if previewAsSource {
                WorkspaceCodeView(source: text, language: "markdown")
            } else if text.utf16.count > 200_000 {
                unsupportedView(
                    icon: "doc.text", title: "File too large to preview",
                    detail: "\(WorkspaceFileFormat.bytes(file?.size ?? 0)) · Switch to Source.")
            } else {
                ScrollView {
                    ClaudeMarkdownView(
                        text, theme: ClaudeProse.theme(bodySize: 14)
                    ) { action in
                        if case .openLink(let url) = action { openURL(url) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
        } else {
            unsupportedView(
                icon: "doc.text", title: "No content",
                detail: "The daemon returned no text for this file.")
        }
    }

    /// An HTML page with the Preview / Source control: Preview is the sandboxed web view
    /// (JavaScript off, no network), Source the highlighted markup (UX spec §6).
    @ViewBuilder private var htmlContent: some View {
        if let text = file?.textContent {
            if previewAsSource {
                WorkspaceCodeView(source: text, language: "html")
            } else if text.utf16.count > 200_000 {
                unsupportedView(
                    icon: "doc.text", title: "File too large to preview",
                    detail: "\(WorkspaceFileFormat.bytes(file?.size ?? 0)) · Switch to Source.")
            } else {
                sandboxedPreview(WorkspaceFileWebDocument.html(text, dark: colorScheme == .dark))
            }
        } else {
            unsupportedView(
                icon: "doc.text", title: "No content",
                detail: "The daemon returned no text for this file.")
        }
    }

    /// An SVG file: decoded from the daemon's base64 image bytes and rendered by the sandboxed
    /// web view, fitted to the width. No scripts can run (UX spec §6).
    @ViewBuilder private func svgContent(_ file: FileExplorerFile) -> some View {
        if let data = imageData, let source = String(data: data, encoding: .utf8) {
            sandboxedPreview(WorkspaceFileWebDocument.svg(source, dark: colorScheme == .dark))
        } else {
            unsupportedView(
                icon: "photo", title: "Image can't be shown",
                detail: "The daemon sent SVG bytes this view can't decode.")
        }
    }

    /// The file preview web view: scrollable, filling the viewer, page JavaScript off.
    private func sandboxedPreview(_ html: String) -> some View {
        SandboxedHTMLView(
            html: html, heightFloor: 0, heightCeiling: 0, onHeightChange: { _ in },
            fillsFrame: true, allowsScripts: false
        )
    }

    /// Images render zoomable: pinch, drag while zoomed, double-tap to toggle 1x/2x.
    @ViewBuilder private func zoomableImage(_ file: FileExplorerFile) -> some View {
        if let data = imageData, let uiImage = UIImage(data: data) {
            ZoomableImageView(image: uiImage)
        } else {
            unsupportedView(
                icon: "photo", title: "Image can't be shown",
                detail: "The daemon sent image bytes this view can't decode.")
        }
    }

    /// Binary, non-image files: a calm message and a share action.
    private func unsupportedShareableView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.glyph(.hero, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                shareCurrentFile()
            } label: {
                if isSharing {
                    ProgressView().controlSize(.small)
                        .frame(height: 36)
                        .padding(.horizontal, 20)
                } else {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 36)
                        .padding(.horizontal, 16)
                        .background(Palette.chip, in: .capsule)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSharing)
            .accessibilityLabel("Share file")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Reads the bytes into memory and presents `fileExporter` (socket read via WorkspaceShare;
    /// the HTTP token route is unreachable from this client).
    private func saveCurrentFile() {
        guard !isPreparingSave, let file else { return }
        isPreparingSave = true
        shareFailure = nil
        Haptics.selection()
        Task {
            do {
                let name = file.path.split(separator: "/").last.map(String.init)
                let payload = try await WorkspaceShare.prepareExport(
                    checkout, path: relativePath, name: name)
                exportName = payload.displayName
                exportType = payload.contentType
                exportDocument = WorkspaceExportDocument(data: payload.data)
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
        Haptics.selection()
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

    // MARK: Calm states

    private func unsupportedView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.glyph(.hero, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                Haptics.selection()
                Task { await files.read(relativePath) }
            } label: {
                Text("Retry")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 32)
                    .background(Palette.chip, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A file's text, monospaced, with the syntax theme in force, a line-number gutter, horizontal
/// scroll for long lines and selection. Line heights match on both sides so the gutter and the
/// text line up. Highlighting runs on `CodeHighlighter` (off main) and falls back to plain text.
struct WorkspaceCodeView: View {
    let source: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme

    static let fontSize: CGFloat = 12
    private static let lineSpacing: CGFloat = 6 // 12 + 6 = 18 pt lines

    private var lines: [Substring] { source.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    // Same font and pitch on both sides: each content line box is exactly one gutter row.
                    if lines.count <= 4000 {
                        Gutter(count: lines.count)
                    }
                    Text(highlighted ?? AttributedString(source))
                        .font(.paseo(.codeSmall))
                        .lineSpacing(Self.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .scrollBounceBehavior(.basedOnSize)
        .codeTypeScale()
        // Same fallback behavior as the Markdown code blocks: plain text until (or unless) the
        // highlighter answers. Off main, so a large file never blocks the viewer's paint.
        .task(id: highlightKey) {
            let result = await CodeHighlighter.shared.highlight(
                source, language: language, theme: syntaxTheme)
            if highlighted != result { highlighted = result }
        }
        // A different file of the same length would otherwise keep the previous tokens.
        .onChange(of: source) { _, _ in highlighted = nil }
    }

    @State private var highlighted: AttributedString?

    private var syntaxTheme: ClaudeCodeSyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    private var highlightKey: String {
        "\(syntaxTheme.rawValue)/\(language ?? "")/\(source.utf16.count)"
    }

    private struct Gutter: View {
        let count: Int

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(1...max(count, 1), id: \.self) { number in
                    Text(verbatim: String(number))
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.captionInk)
                        .frame(width: CGFloat(gutterWidth), alignment: .trailing)
                }
            }
            .accessibilityHidden(true)
        }

        private var gutterWidth: CGFloat {
            let digits = max(2, String(count).count)
            return CGFloat(digits) * 8 + 4
        }
    }
}
/// A zoomable image: pinch to zoom, drag to pan while zoomed, double-tap to toggle 1x/2x.
private struct ZoomableImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(5, max(1, value))
                        }
                        .onEnded { _ in
                            if scale <= 1.05 { scale = 1; offset = .zero; lastOffset = .zero }
                        })
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
                .onTapGesture(count: 2) {
                    withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }
                .accessibilityLabel("Zoomable image")
        }
        .background(Palette.codeSurface)
    }

    private func fittedSize(in size: CGSize) -> CGSize {
        let aspect = image.size.width / max(image.size.height, 1)
        let bounds = CGSize(width: size.width, height: size.height)
        var width = bounds.width
        var height = width / aspect
        if height > bounds.height {
            height = bounds.height
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }
}
#endif
