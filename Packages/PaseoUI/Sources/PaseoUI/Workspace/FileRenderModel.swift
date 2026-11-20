#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One file's decoded content. Built once per `(path, revision, theme)` off the main actor for
/// the decode/split, and on `CodeHighlighter` (an actor) for the highlighting.
struct FileRenderModel: @unchecked Sendable {
    enum Payload {
        case text(text: String, highlighted: AttributedString?, lines: [String])
        case image(data: Data, image: UIImage)
        case svg(source: String)
        case binary
    }

    let payload: Payload

    /// The plain text, for Markdown/HTML previews and copy.
    var text: String? {
        switch payload {
        case .text(let text, _, _): return text
        case .svg(let source): return source
        case .image, .binary: return nil
        }
    }

    @MainActor
    static func make(
        file: FileExplorerFile, language: String?, theme: ClaudeCodeSyntaxTheme, maxPixel: Int
    ) async -> FileRenderModel {
        let decoded = await Task.detached(priority: .userInitiated) {
            DecodedFile(file: file, maxPixel: maxPixel)
        }.value
        switch decoded.payload {
        case .text(let text, let lines):
            let highlighted = lines.count <= 500
                ? await highlightedText(text, language: language, theme: theme) : nil
            return FileRenderModel(payload: .text(text: text, highlighted: highlighted, lines: lines))
        case .image(let data, let image):
            return FileRenderModel(payload: .image(data: data, image: image))
        case .svg(let source):
            return FileRenderModel(payload: .svg(source: source))
        case .binary:
            return FileRenderModel(payload: .binary)
        }
    }

    /// `CodeHighlighter` runs off the main actor (R9); nil means keep the plain text.
    private static func highlightedText(
        _ text: String, language: String?, theme: ClaudeCodeSyntaxTheme
    ) async -> AttributedString? {
        await CodeHighlighter.shared.highlight(text, language: language, theme: theme)
    }
}
#endif
