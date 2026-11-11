#if canImport(UIKit)
import Foundation

/// Sandboxed documents for the Files viewer's SVG and HTML previews (UX spec §6, E3 §3.3).
///
/// SVG stays a static document: inline styles and `data:`/`blob:` images only, no script, no
/// network. HTML runs the page's own scripts — most real pages build their content with
/// JavaScript — in a non-persistent data store, and may fetch subresources over https so CDN
/// libraries load. No height reporter is injected: the viewer's web view fills its frame and
/// scrolls, and a top-level navigation opens in Safari instead (`SandboxedHTMLView`).
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
            svg { width: 100%; height: auto; display: block; }
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
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https:; style-src 'unsafe-inline' https:; img-src https: data: blob:; font-src https: data:; connect-src https:; media-src https: data: blob:; frame-src https:; object-src 'none'; base-uri 'none'">
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
