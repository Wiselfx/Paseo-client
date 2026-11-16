// features: F04
// Fixture: image loading outside the media pipeline.
import SwiftUI

struct BadMedia: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) // hit: H21
    }

    func decode(_ data: Data) -> UIImage? {
        UIImage(data: data) // hit: H21
    }
}
