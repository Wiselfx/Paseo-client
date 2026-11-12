#if canImport(UIKit)
import CryptoKit
import PaseoStore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - RichFileCard (G10 C10)

// NOTE: RemoteImagePipeline/G10: a standalone path line is a file card; a path inside
// a sentence stays a chip (`RichPathChip`). Nothing downloads until tapped — except a
// PDF thumbnail under 5 MB. Text, code and image files open in the workspace viewer
// (the existing path); everything else downloads (64 MB cap) into the cache and opens
// in Quick Look.

/// One standalone file path: icon or PDF thumbnail, name, parent directory and size,
/// chevron. The box is reserved from the first layout; only the thumbnail fades in.
struct RichFileCard: View {
    let path: String

    @Environment(\.richActions) private var richActions
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The parent listing's entry, for the lazy size. Nil until the listing answers.
    @State private var fileSize: Int64?
    @State private var listedDirectories = false
    /// The first PDF page, decoded off main. Nil until the ≤ 5 MB fetch lands.
    @State private var pdfThumbnail: UIImage?
    @State private var downloading = false
    @State private var downloadedURL: URL?
    @State private var showQuickLook = false
    @State private var showShare = false
    @State private var overLimit = false
    @State private var loadFailed = false

    private var fileExtension: String {
        (path as NSString).pathExtension.lowercased()
    }

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// The parent directory, middle-truncated; the card never shows a full cwd.
    private var parentDirectory: String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == "." { return "~" }
        if parent.count <= 28 { return parent }
        return "…" + parent.suffix(27)
    }

    private var isPDF: Bool { fileExtension == "pdf" }

    private var metaText: String? {
        guard let fileSize else { return parentDirectory }
        return "\(parentDirectory) · \(Self.byteCount(fileSize))"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func byteCount(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    private var ref: DaemonFileRef? {
        guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
        return DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil)
    }

    /// Text, code and images open in the workspace file viewer (the existing path).
    private var opensInWorkspaceViewer: Bool {
        if isPDF { return false }
        if let type = UTType(filenameExtension: fileExtension) {
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) { return true }
            if type.conforms(to: .image) { return true }
        }
        return Self.textLikeExtensions.contains(fileExtension)
    }

    private static let textLikeExtensions: Set<String> = [
        "txt", "md", "markdown", "mdown", "mkdn", "json", "yaml", "yml", "toml", "xml",
        "csv", "tsv", "log", "diff", "patch",
    ]

    /// SF Symbols by type family (flagged for the gate: names, not behavior).
    private var glyph: String {
        switch fileExtension {
        case "pdf": "doc.richtext"
        case "csv", "tsv": "tablecells"
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar": "archivebox"
        case "mp3", "m4a", "wav", "aac", "caf", "aiff", "flac", "opus": "waveform"
        case "mp4", "mov", "m4v", "webm": "film"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp": "photo"
        case "doc", "docx", "pages", "rtf", "odt": "doc.richtext"
        case "xls", "xlsx", "numbers", "ods": "tablecells"
        case "key", "ppt", "pptx", "odp": "rectangle.on.rectangle"
        default: "doc"
        }
    }

    var body: some View {
        Button {
            open()
        } label: {
            PaseoCard(content:
                HStack(spacing: Space.sm) {
                    if let pdfThumbnail {
                        Image(uiImage: pdfThumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: glyph)
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: Metrics.hitSize - Space.md, alignment: .center)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let metaText {
                            Text(metaText)
                                .font(.paseo(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if downloading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Palette.secondaryInk)
                            .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                            .accessibilityLabel("Downloading file")
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.tertiaryInk)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
                .contentShape(.rect))
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .paseoCardMenu(
            openTitle: opensInWorkspaceViewer ? "Open" : nil,
            onOpen: opensInWorkspaceViewer ? { open() } : nil,
            onShare: shareTarget != nil ? { showShare = true } : nil,
            copyTitle: "Copy path",
            copyText: path,
            filePath: path)
        .paseoCardAccessibility(kind: "File", title: fileName, meta: metaText, isButton: true)
        .task(id: path) { await loadMetadata() }
        .fullScreenCover(isPresented: $showQuickLook) {
            if let downloadedURL {
                QuickLookPreview(url: downloadedURL)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShare) {
            if let shareTarget {
                ActivityView(items: [shareTarget])
            }
        }
    }

    // MARK: Lazy size and PDF thumbnail

    /// The parent listing answers the size without reading the file; a PDF at or
    /// under 5 MB is worth one bounded fetch for its thumbnail.
    @MainActor
    private func loadMetadata() async {
        guard fileSize == nil, !listedDirectories else { return }
        listedDirectories = true
        guard let workspaceID = richActions?.daemonWorkspaceID,
            let list = await richActions?.listDaemonDirectory(workspaceID, parentPath) else { return }
        guard !Task.isCancelled else { return }
        if let entry = list.first(where: { entry in
            (entry.path as NSString).lastPathComponent == fileName
        }) {
            fileSize = Int64(entry.size)
        }
        await loadPDFThumbnailIfSmall()
    }

    @MainActor
    private func loadPDFThumbnailIfSmall() async {
        guard isPDF, pdfThumbnail == nil, let size = fileSize, size <= 5 * 1024 * 1024,
            let ref
        else { return }
        guard case .bytes(let bytes) = await MediaPipeline.shared.fetchDaemonFile(ref: ref, maxBytes: 5 * 1024 * 1024) else { return }
        let width = 44 * displayScale
        let thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let document = PDFDocument(data: bytes.data), let page = document.page(at: 0) else {
                return nil
            }
            let box = page.bounds(for: .mediaBox)
            let ratio = box.width / max(box.height, 1)
            return page.thumbnail(of: CGSize(width: width, height: max(width / max(ratio, 0.01), 1)), for: .mediaBox)
        }.value
        guard !Task.isCancelled else { return }
        pdfThumbnail = thumbnail
    }

    // MARK: Open

    private func open() {
        if opensInWorkspaceViewer {
            richActions?.openFile(path)
            return
        }
        // The 64 MB cap row and the failure row both retry on tap: the cap retries
        // into the same honest answer, a failure retries the fetch.
        if overLimit || loadFailed {
            overLimit = false
            Haptics.light()
            Task { @MainActor in
                await downloadAndPreview()
            }
            return
        }
        Haptics.light()
        Task { @MainActor in
            await downloadAndPreview()
        }
    }

    private var shareTarget: URL? { downloadedURL }

    /// Downloads (64 MB cap) into the cache, then Quick Look when the system can
    /// preview the kind, else the share sheet. The card keeps its box throughout.
    @MainActor
    private func downloadAndPreview() async {
        guard !downloading, let ref else { return }
        downloading = true
        defer { downloading = false }
        let result = await MediaPipeline.shared.fetchDaemonFile(ref: ref, maxBytes: 64 * 1024 * 1024)
        guard !Task.isCancelled else { return }
        switch result {
        case .bytes(let fetched):
            guard let url = Self.cachedFileURL(for: path, workspaceID: ref.workspaceID),
                (try? fetched.data.write(to: url, options: .atomic)) != nil
            else {
                loadFailed = true
                return
            }
            if QLPreviewController.canPreview(url as NSURL) {
                downloadedURL = url
                showQuickLook = true
            } else {
                downloadedURL = url
                showShare = true
            }
        case .tooLarge:
            overLimit = true
        case .unavailable:
            loadFailed = true
        }
    }

    private static func cachedFileURL(for path: String, workspaceID: String) -> URL? {
        // Stable across launches (unlike `Hasher`), so the LRU directory does not
        // accumulate one entry per launch.
        var digest = SHA256()
        digest.update(data: Data("\(workspaceID)\0\(path)".utf8))
        let key = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "daemon-files", directoryHint: .isDirectory)
            .appending(path: key + "-" + (path as NSString).lastPathComponent, directoryHint: .notDirectory)
    }
}
#endif
