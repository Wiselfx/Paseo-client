#if canImport(UIKit)
import SwiftUI
import UIKit

/// The project's icon (or its first letter), name and root path at the top of its settings.
struct ProjectHero: View {
    let title: String
    let path: String
    let image: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.chip)
                    .frame(width: 60, height: 60)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(.circle)
                } else {
                    Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.paseo(.largeTitle))
                        .foregroundStyle(Palette.ink)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.paseo(.title))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(path)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
        }
        .padding(.vertical, 2)
    }
}
#endif
