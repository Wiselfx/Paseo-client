// features: F01 F04 F05
// Fixture: GOOD media shapes: width read with onGeometryChange written on change, decoding off the body
// through ImageIO thumbnails in a function, a task keyed by id.
import ImageIO
import SwiftUI

struct GoodCard: View, Equatable {
    let url: URL
    @State private var width: CGFloat = 0

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.url == rhs.url }

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
            }
            .task(id: url) { _ = await GoodCard.downsample(url, width: width) }
    }

    static func downsample(_ url: URL, width: CGFloat) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: width]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
