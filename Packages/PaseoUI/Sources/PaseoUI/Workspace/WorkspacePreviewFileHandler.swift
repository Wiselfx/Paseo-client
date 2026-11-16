#if canImport(UIKit)
import Foundation
import PaseoStore
import UniformTypeIdentifiers
import WebKit

/// Serves the workspace files an HTML preview references (`paseo-file://<workspaceId>/<path>`),
/// read-only, from the checkout's file API (E3b).
///
/// The preview document is loaded in a non-persistent store with page scripts on and a
/// `paseo-file:` base, so `./style.css`, `/logo.png` and `fetch("data.json")` reach this handler.
/// It is the only way a preview can read the workspace, and `PreviewFileScheme` decides what a
/// request may address: another workspace, an escaping `..`, or an empty path never reaches the
/// daemon. Every resource is capped, and a read is cancelled when WebKit stops the task.
@MainActor
final class WorkspacePreviewFileHandler: NSObject, WKURLSchemeHandler {
    private let files: WorkspaceFiles
    private let workspaceId: String
    /// The live requests, so `stop` can drop exactly one and a superseded read can never write.
    private var requests: [ObjectIdentifier: any WKURLSchemeTask] = [:]
    private var reads: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(files: WorkspaceFiles, workspaceId: String) {
        self.files = files
        self.workspaceId = workspaceId
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        // The task itself never leaves the main actor: the read is identified by its id.
        requests[id] = urlSchemeTask
        reads[id]?.cancel()
        reads[id] = Task { @MainActor [weak self] in
            await self?.serve(id)
            self?.finish(id)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        finish(ObjectIdentifier(urlSchemeTask as AnyObject))
    }

    private func finish(_ id: ObjectIdentifier) {
        reads.removeValue(forKey: id)?.cancel()
        requests.removeValue(forKey: id)
    }

    private func serve(_ id: ObjectIdentifier) async {
        guard let url = requests[id]?.request.url,
            let resolved = PreviewFileScheme.resolve(url),
            resolved.workspaceId.caseInsensitiveCompare(workspaceId) == .orderedSame
        else {
            fail(id, code: 400)
            return
        }
        do {
            let file = try await files.fetch(
                resolved.path, maxBytes: PreviewFileScheme.maxResourceBytes)
            let data = try await Self.bytes(of: file)
            guard data.count <= PreviewFileScheme.maxResourceBytes else {
                fail(id, code: 413)
                return
            }
            // `stop` may have arrived while the daemon was reading: never touch a dead task.
            guard !Task.isCancelled, let task = requests[id] else { return }
            // `URLResponse` rather than `HTTPURLResponse`: the scheme is not http, and WebKit is
            // happy with the plain response (the MIME type is what the page needs).
            let response = URLResponse(
                url: url, mimeType: Self.mimeType(for: file, path: resolved.path),
                expectedContentLength: data.count, textEncodingName: "utf-8")
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            fail(id, code: 404)
        }
    }

    /// The daemon sends text inline and binary as base64. Neither a 16 MB `String`→`Data` copy
    /// nor a base64 decode belongs on main: the preview is being drawn while the page waits.
    private static func bytes(of file: FileExplorerFile) async throws -> Data {
        guard let content = file.content else { throw PreviewFileError.empty }
        if file.encoding == .utf8 {
            return await Task.detached(priority: .userInitiated) { Data(content.utf8) }.value
        }
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            Data(base64Encoded: content)
        }).value else { throw PreviewFileError.undecodable }
        return data
    }

    /// The extension wins: WebKit applies a stylesheet or a module only when the type is exactly
    /// `text/css` / `text/javascript`, and a daemon that reports `text/plain` would break the page.
    /// The daemon's own type is the fallback for an extensionless file.
    private static func mimeType(for file: FileExplorerFile, path: String) -> String {
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext),
            let mime = type.preferredMIMEType {
            return mime
        }
        if let mime = file.mimeType, !mime.isEmpty { return mime }
        return "application/octet-stream"
    }

    private func fail(_ id: ObjectIdentifier, code: Int) {
        guard !Task.isCancelled, let task = requests[id] else { return }
        task.didFailWithError(
            NSError(
                domain: "paseo-file", code: code,
                userInfo: [NSLocalizedDescriptionKey: "The preview could not read this file."]))
    }

    private enum PreviewFileError: Error {
        case empty, undecodable
    }
}
#endif
