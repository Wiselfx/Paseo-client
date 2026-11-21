#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Code view

/// A file's text, monospaced, with the syntax theme in force, a line-number gutter, horizontal
/// scroll for long lines and selection. Files over 500 lines render lazy line rows; smaller files
/// keep one selectable `Text`, as before.
struct WorkspaceCodeView: View, Equatable {
    /// R-2: the viewer re-runs for toasts, reveal and copy state; an unchanged document (same text, same
    /// highlighting) skips this body and the whole-file `AttributedString` it builds.
    nonisolated static func == (lhs: WorkspaceCodeView, rhs: WorkspaceCodeView) -> Bool {
        lhs.text == rhs.text && lhs.highlighted == rhs.highlighted
    }

    /// The plain source, kept for the copy path and for the long-file rows.
    let text: String
    /// The highlighted whole document; nil for long files (highlighter cap) and raw source.
    let highlighted: AttributedString?
    /// The document split once, not per body.
    let lines: [String]

    static let fontSize: CGFloat = 12
    private static let lineSpacing: CGFloat = 6  // 12 + 6 = 18 pt lines

    private var isLong: Bool { lines.count > 500 }

    /// Digits of the widest line number, at least two.
    private var gutterDigits: Int { max(2, String(max(lines.count, 1)).count) }

    var body: some View {
        if isLong {
            longContent
        } else {
            shortContent
        }
    }

    private var shortContent: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.md) {
                    // Same font and pitch on both sides: each content line box is exactly one gutter row.
                    Gutter(count: lines.count)
                    Text(highlighted ?? AttributedString(text))
                        .font(.paseo(.codeSmall))
                        .lineSpacing(Self.lineSpacing)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .padding(Space.md)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .scrollBounceBehavior(.basedOnSize)
        .codeTypeScale()
    }

    /// One two-axis scroll view: a horizontal scroll ancestor would make the stack lay out every
    /// row, so the lines scroll both ways from the same view.
    private var longContent: some View {
        ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.enumerated(), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            CodeLineNumber(
                                number: index + 1, digits: gutterDigits, font: .paseo(.codeCaption))
                            Text(line.isEmpty ? " " : line)
                                .font(.paseo(.codeSmall))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, Space.md)
                        .padding(.vertical, 1.5)
                    }
                }
                .padding(.vertical, Space.sm)
        }
        .scrollBounceBehavior(.basedOnSize)
        .codeTypeScale()
    }

    private struct Gutter: View {
        let count: Int

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(1...max(count, 1), id: \.self) { number in
                    CodeLineNumber(number: number, digits: digits, font: .paseo(.codeSmall))
                }
            }
            .accessibilityHidden(true)
        }

        /// Digits of the widest line number, at least two.
        private var digits: Int { max(2, String(count).count) }
    }
}
#endif
