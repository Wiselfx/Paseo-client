#if canImport(UIKit)
import Foundation

/// Sandboxed documents for the Files viewer's SVG and HTML previews (UX spec §6).
///
/// Both are offline documents: the CSP allows inline styles and `data:`/`blob:` images only,
/// blocks every script (`script-src 'none'`) and every network fetch (`default-src 'none'`,
/// `connect-src 'none'`), so a preview never runs code from the workspace or calls out.
/// No height reporter is injected: the viewer's web view fills its frame and scrolls.
enum WorkspaceFileWebDocument {
    /// An SVG file, inline in a minimal document, fitted to the width of the view.
    static func svg(_ source: String, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data: blob:">
            <style>:root { color-scheme: \(scheme); }
            html, body { margin: 0; padding: 0; background: transparent; }
            svg { max-width: 100%; height: auto; display: block; }
            </style>
            </head>
            <body>
            \(source)
            </body>
            </html>
            """
    }

    /// A workspace HTML file, in a document whose head carries the sandbox rules. A file that
    /// is only a fragment is wrapped; one with its own `<head>` gets the rules inserted there.
    static func html(_ source: String, dark: Bool) -> String {
        injecting(head: head(dark: dark), into: source)
    }

    private static func head(dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        let text = dark ? "#e6e6e6" : "#1a1a1a"
        return """
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; script-src 'none'; connect-src 'none'; media-src data: blob:; frame-src 'none'; object-src 'none'; base-uri 'none'">
            <style>:root { color-scheme: \(scheme); }
            html, body { background: transparent; color: \(text); font-family: -apple-system, sans-serif; }
            </style>
            """
    }

    /// Puts the sandbox head into the document's own `<head>` when it has one, under `<html>`
    /// when it has that, and wraps a bare fragment otherwise.
    private static func injecting(head: String, into source: String) -> String {
        if let headStart = source.range(of: "<head", options: .caseInsensitive),
            let headEnd = source.range(of: ">", range: headStart.upperBound..<source.endIndex)
        {
            var copy = source
            copy.insert(contentsOf: head, at: headEnd.upperBound)
            return copy
        }
        if let htmlStart = source.range(of: "<html", options: .caseInsensitive),
            let htmlEnd = source.range(of: ">", range: htmlStart.upperBound..<source.endIndex)
        {
            var copy = source
            copy.insert(contentsOf: "<head>\(head)</head>", at: htmlEnd.upperBound)
            return copy
        }
        return "<!DOCTYPE html><html><head>\(head)</head><body>\(source)</body></html>"
    }
}
#endif
