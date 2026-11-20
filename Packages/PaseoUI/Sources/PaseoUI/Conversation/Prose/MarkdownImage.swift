import Foundation
import Markdown
import PaseoStore

public struct MarkdownImage: Equatable, Sendable {
    public var source: String
    public var title: String?
    public var alt: String
    public init(source: String, title: String? = nil, alt: String) {
        self.source = source
        self.title = title
        self.alt = alt
    }
}
