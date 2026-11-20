import Foundation
import Markdown
import PaseoStore

/// No action performs I/O. The host owns links, images, clipboard and unsupported extensions.
@nonexhaustive public enum MarkdownAction: Equatable, Sendable {
    case openLink(URL), image(MarkdownImage), copyCode(String)
    case expandCode(language: String?, content: String)
    /// "Preview" on a closed html/svg fence (G5 C8): never auto-rendered, always explicit.
    case previewCode(language: String?, content: String)
    case unsupported(kind: MarkdownUnsupportedKind, source: String)
    var presentationURL: URL? {
        var components = URLComponents()
        components.scheme = "claude-markdown"
        components.host = "presentation"
        switch self {
        case .image(let image):
            components.path = "/image"
            components.queryItems = [
                .init(name: "source", value: image.source), .init(name: "alt", value: image.alt),
                .init(name: "title", value: image.title)
            ]
        case .unsupported(let kind, let source):
            components.path = "/unsupported"
            components.queryItems = [.init(name: "kind", value: kind.rawValue), .init(name: "source", value: source)]
        default: return nil
        }
        return components.url
    }
    static func decodePresentationURL(_ url: URL) -> Self? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "claude-markdown",
            c.host == "presentation"
        else { return nil }
        func value(_ name: String) -> String? { c.queryItems?.first(where: { $0.name == name })?.value }
        guard let source = value("source") else { return nil }
        if c.path == "/image" { return .image(.init(source: source, title: value("title"), alt: value("alt") ?? "")) }
        if c.path == "/unsupported", let raw = value("kind"), let kind = MarkdownUnsupportedKind(rawValue: raw) {
            return .unsupported(kind: kind, source: source)
        }
        return nil
    }
}
