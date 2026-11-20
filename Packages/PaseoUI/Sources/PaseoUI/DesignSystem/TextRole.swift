#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

/// A text role: one face, one size and one Dynamic Type style, resolved once.
///
/// Views never name a size. Weight is applied on top of the role, except `headline`, which
/// carries its own semibold.
enum TextRole: Hashable, Sendable {
    /// Serif 28: sidebar "Paseo", hero lines.
    case largeTitle
    /// Serif 20: chat header title, sheet hero titles.
    case title
    /// Serif 14: the work group's summary line and other process headings.
    case processTitle
    /// Serif 13: a tool row's title and the opened reasoning text.
    case process
    /// Sans 17 semibold: section and row titles that lead.
    case headline
    /// Sans 17: chat body, composer, settings rows.
    case body
    /// Sans 15: secondary rows, buttons, chips.
    case callout
    /// Sans 13: metadata, captions under rows.
    case footnote
    /// Sans 12: small metadata.
    case caption
    /// Sans 11: badges, pills, counters.
    case caption2
    /// Mono 13: code blocks, tool output, diffs.
    case code
    /// Mono 12: dense code (gutters, chips).
    case codeSmall
    /// Mono 11: line numbers, tiny mono labels.
    case codeCaption
    /// Serif 34: the home hero greeting.
    case hero

    /// The bundled face family this role reads in.
    enum Face: Sendable { case serif, sans, mono }

    var face: Face {
        switch self {
        case .largeTitle, .title, .processTitle, .process, .hero: .serif
        case .code, .codeSmall, .codeCaption: .mono
        case .headline, .body, .callout, .footnote, .caption, .caption2: .sans
        }
    }

    var size: CGFloat {
        switch self {
        case .largeTitle: 28
        case .title: 20
        case .processTitle: 14
        case .process: 13
        case .headline, .body: 17
        case .callout: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        case .code: 13
        case .codeSmall: 12
        case .codeCaption: 11
        case .hero: 34
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title3
        case .processTitle: .subheadline
        case .process: .footnote
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        case .code: .footnote
        case .codeSmall: .caption
        case .codeCaption: .caption2
        case .hero: .largeTitle
        }
    }

    /// `headline` is the one role that bakes its weight; everything else takes it from the caller.
    var bakedWeight: Font.Weight? {
        self == .headline ? .semibold : nil
    }
}
#endif
