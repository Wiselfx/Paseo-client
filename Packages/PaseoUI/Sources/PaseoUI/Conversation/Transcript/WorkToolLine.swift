#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The verb, then the target in mono, middle-truncated so both ends of a path or command show.
struct WorkToolLine: View {
    let verb: String
    let target: String?
    var ink: Color = Palette.secondaryInk

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verb)
                .font(.paseo(.processTitle, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
            if let target {
                Text(target)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
#endif
