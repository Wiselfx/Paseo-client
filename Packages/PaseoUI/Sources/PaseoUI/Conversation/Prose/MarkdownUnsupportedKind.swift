import Foundation
import Markdown
import PaseoStore

public enum MarkdownUnsupportedKind: String, Equatable, Sendable { case html, math, footnote, other }
