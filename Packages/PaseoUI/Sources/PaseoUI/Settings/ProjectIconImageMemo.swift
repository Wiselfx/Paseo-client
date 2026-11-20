#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The decoded project icon for the bytes it came from.
@MainActor final class ProjectIconImageMemo {
    private var data: Data?
    private var image: UIImage?

    func image(for data: Data) -> UIImage? {
        if self.data == data { return image }
        self.data = data
        image = UIImage(data: data)
        return image
    }
}
#endif
