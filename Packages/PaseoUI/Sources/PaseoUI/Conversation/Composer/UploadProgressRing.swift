#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// The thin progress ring on an uploading attachment. It is its own view so that only the ring
/// reads `progress`, which `ConversationUpload` writes after every chunk (about 400 times for a
/// 50 MB file): were the tray to read it, each write would re-run the whole composer.
struct UploadProgressRing: View {
    /// The channel the upload rides; nil reads as no progress yet.
    let uploads: ConversationUpload?
    let diameter: CGFloat
    let tint: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0.05, uploads?.progress ?? 0))
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(-90))
    }
}
#endif
