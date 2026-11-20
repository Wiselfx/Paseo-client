import Foundation
import Markdown
import PaseoStore

public struct MarkdownListItem: Equatable, Sendable {
    public var checked: Bool?
    public var blocks: [MarkdownBlock]
    public init(checked: Bool? = nil, blocks: [MarkdownBlock]) {
        self.checked = checked
        self.blocks = blocks
    }
}
