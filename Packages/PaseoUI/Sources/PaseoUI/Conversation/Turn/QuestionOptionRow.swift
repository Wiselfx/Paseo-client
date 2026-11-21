#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// One selectable option in a question: a radio (single-select) or checkbox (multi-select)
/// mark, the label, and its description. The section owns the selection; this row only draws it.
struct QuestionOptionRow: View {
    let option: QuestionFormOption
    let selected: Bool
    let multiSelect: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    if multiSelect {
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .stroke(selected ? Palette.ink : Palette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.glyph(.small, weight: .bold))
                                .foregroundStyle(Palette.ink)
                        }
                    } else {
                        Circle()
                            .stroke(selected ? Palette.ink : Palette.tertiaryInk, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        if selected {
                            Circle().fill(Palette.ink).frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(selected ? Palette.adaptive(light: 0.965, dark: 0.10) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
