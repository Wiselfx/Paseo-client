#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// Loads and crops the sheets. Everything is read from the app bundle once and cached; the
/// art never touches the network.
@MainActor enum CrabSheetLoader {
    private static var sheets: [String: UIImage?] = [:]
    private static var crops: [String: UIImage?] = [:]

    static func image(animation: CrabAnimation, ink: Bool) -> UIImage? {
        let key = ink ? "\(animation.rawValue)-ink" : animation.rawValue
        if let cached = sheets[key] { return cached }
        let url =
            Bundle.module.url(forResource: key, withExtension: "png", subdirectory: "Crab")
            ?? Bundle.module.url(forResource: key, withExtension: "png")
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }
        sheets[key] = image
        return image
    }

    /// The crop for one frame, or nil when the sheet can't produce it.
    static func frame(animation: CrabAnimation, index: Int, ink: Bool) -> UIImage? {
        let key = "\(animation.rawValue)-\(index)-\(ink ? "ink" : "color")"
        if let cached = crops[key] { return cached }
        guard let sheet = image(animation: animation, ink: ink), let cgImage = sheet.cgImage else {
            crops[key] = nil
            return nil
        }
        let spec = animation.sheet
        let box = spec.box
        let columns = CrabAnimation.columns
        let column = index % columns
        let row = index / columns
        // The sheets store 1 px per cell; a frame is `box` cells, cropped edge-to-edge.
        guard
            let image = cgImage.cropping(
                to: CGRect(
                    x: CGFloat(column * box.width),
                    y: CGFloat(row * box.height),
                    width: CGFloat(box.width),
                    height: CGFloat(box.height)))
        else {
            crops[key] = nil
            return nil
        }
        // Raw pixels stay raw: the view scales with nearest-neighbour interpolation.
        let result = UIImage(cgImage: image, scale: 1, orientation: .up)
        crops[key] = result
        return result
    }
}
#endif
