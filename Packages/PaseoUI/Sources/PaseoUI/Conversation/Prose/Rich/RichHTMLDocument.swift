#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// HTML documents for the web-backed rich blocks. All are offline: the CSP forbids
/// every source except inline styles/scripts (html) or nothing at all (SVG), and image
/// loads to data:/blob: URLs.
enum RichHTMLDocument {
    /// Reports the document's height once per animation frame and only when it moved by half a
    /// point or more (R9 §2). A `ResizeObserver` on the body replaces the whole-document
    /// `MutationObserver` where it exists; the observer is only the fallback.
    private static let heightReporter = """
        <script>(function(){var last=-1,queued=false;function post(){queued=false;var t=document.documentElement,b=document.body;var h=Math.max(t?t.scrollHeight:0,b?b.scrollHeight:0);if(Math.abs(h-last)<0.5)return;last=h;if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vizHeight){window.webkit.messageHandlers.vizHeight.postMessage(h);}}function schedule(){if(queued)return;queued=true;requestAnimationFrame(post);}if(window.ResizeObserver){new ResizeObserver(schedule).observe(document.documentElement);if(document.body)new ResizeObserver(schedule).observe(document.body);if(document.documentElement.firstElementChild)new ResizeObserver(schedule).observe(document.documentElement.firstElementChild);}else{new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,attributes:true,characterData:true});}window.addEventListener('load',schedule);schedule();})();</script>
        """

    /// A rendered artifact SVG (mermaid output, G4/G5): the same static guarantees as the
    /// raw block, but sized for a full-screen page instead of a card — the drawing fills
    /// the viewport width at its intrinsic ratio and the page scrolls what exceeds it.
    /// No height reporter: the page is not sized to its content.
    static func artifactSVG(source: String, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
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

    /// An html fence or `.html` file for the artifact page: a full document when the source
    /// carries `<html>`, otherwise the fragment wrapped in the offline shell (scripts run,
    /// but the CSP keeps the network closed). The export shares
    /// this same build, so what exports is what the page showed.
    static func artifactHTML(source: String, dark: Bool) -> String {
        if source.lowercased().contains("<html") { return OfflineCSP.inject(into: source) }
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'">
        <style>:root { color-scheme: \(scheme); }
        html, body { margin: 0; padding: 0; background: transparent; color: CanvasText; font-family: -apple-system, sans-serif; }
        </style>
        </head>
        <body>
        \(source)
        </body>
        </html>
        """
    }

    /// A raw `<svg>…</svg>` block, inlined. Scripts never run: the CSP has no `script-src`,
    /// so inline SVG event handlers and `<script>` children are all blocked.
    static func rawSVG(source: String, dark: Bool) -> String {
        let scheme = dark ? "dark" : "light"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <style>:root { color-scheme: \(scheme); }
        html, body { margin: 0; padding: 0; background: transparent; }
        /* Full width: a viewBox-only <svg> is 300x150 by default and would letterbox inside
           the card. height:auto follows the intrinsic ratio from the viewBox or the
           width/height attributes. */
        svg { width: 100%; height: auto; display: block; }
        </style>
        </head>
        <body>
        \(source)
        \(heightReporter)
        </body>
        </html>
        """
    }
}
#endif
