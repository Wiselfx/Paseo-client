#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The Files page's file viewer: text with syntax highlighting and a line-number gutter, an image
/// renderer, and calm messages for binary or too-large files. Top row: back to the folder, the
/// file's name, a copy button when there is something to copy.
struct WorkspaceFileViewer: View {
    let checkout: CheckoutStore
    let relPath: String
    let onBack: () -> Void
    let backLabel: String

    @Environment(\.colorScheme) private var colorScheme
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
    private let typography = ClaudeTypography()

    private var files: WorkspaceFiles { checkout.files }
    private var fileName: String { WorkspaceFileFormat.lastComponent(relPath) }
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
            if isEditing {
                editingContent
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
            .font(typography.mono(WorkspaceCodeView.fontSize))
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClaudePalette.codeBackground)
            .accessibilityLabel("Edit file contents")
    }

    private func saveFailureBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(ClaudePalette.failureInk)
            Text(message)
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.failureInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                saveFailure = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ClaudePalette.failureInk.opacity(0.08))
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
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text(backLabel).font(typography.sans(13)).lineLimit(1)
                }
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .accessibilityLabel("Back to \(backLabel)")
            Spacer(minLength: 4)
            Text(isEditing ? "Editing \(fileName)" : fileName)
                .font(typography.mono(12))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isEditing {
                Button("Cancel") { cancelEdit() }
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(height: 28)
                    .accessibilityLabel("Discard edits")
                Button {
                    Haptics.selection()
                    Task { await saveEdit() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).frame(width: 40, height: 28)
                    } else {
                        Text("Save")
                            .font(typography.sans(13, weight: .semibold))
                            .foregroundStyle(ClaudePalette.ink)
                            .frame(height: 28)
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
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .frame(width: 28, height: 28)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mention in chat")
                }
                if savedFlash {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ClaudePalette.successInk)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Saved")
                } else if canCopy {
                    copyButton
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
                if editableFile != nil { editButton } else { Color.clear.frame(width: 28, height: 28) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var editButton: some View {
        Button {
            Haptics.selection()
            beginEdit()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(ClaudePalette.secondaryInk)
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
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(copied ? ClaudePalette.ink : ClaudePalette.tertiaryInk)
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
                imageView(file)
            case .binary:
                unsupportedView(
                    icon: "doc", title: "Binary file",
                    detail: "This file can't be shown here.\n\(WorkspaceFileFormat.bytes(file.size)) · \(WorkspaceFileFormat.relativeModified(file.modifiedAt))")
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

    private func imageView(_ file: FileExplorerFile) -> some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                ScrollView {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
            } else {
                unsupportedView(
                    icon: "photo", title: "Image can't be shown",
                    detail: "The daemon sent image bytes this view can't decode.")
            }
        }
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
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(title)
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(message)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                Haptics.selection()
                Task { await files.read(relativePath) }
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
}
#endif

#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A file's text, monospaced, with the syntax theme in force, a line-number gutter, horizontal
/// scroll for long lines and selection. Line heights match on both sides so the gutter and the
/// text line up. Highlighting is capped by `ClaudeCodeHighlighter`, which falls back to plain.
struct WorkspaceCodeView: View {
    let source: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme
    private let typography = ClaudeTypography()

    private static let fontSize: CGFloat = 12
    private static let lineSpacing: CGFloat = 6 // 12 + 6 = 18 pt lines

    private var lines: [Substring] { source.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    // Same font and pitch on both sides: each content line box is exactly one gutter row.
                    if lines.count <= 4000 {
                        Gutter(count: lines.count, typography: typography)
                    }
                    Text(highlighted)
                        .font(typography.mono(Self.fontSize))
                        .lineSpacing(Self.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var highlighted: AttributedString {
        let theme: ClaudeCodeSyntaxTheme = colorScheme == .dark ? .dark : .light
        let colored = ClaudeCodeHighlighter.shared.highlight(source, language: language, theme: theme)
        // Same fallback behavior as the Markdown code blocks: plain text if the highlighter refuses.
        return AttributedString(colored, including: \.uiKit)
    }

    private struct Gutter: View {
        let count: Int
        let typography: ClaudeTypography

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(1...max(count, 1), id: \.self) { number in
                    Text("\(number)")
                        .font(typography.mono(WorkspaceCodeView.fontSize))
                        .foregroundStyle(ClaudePalette.captionInk)
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
#endif
