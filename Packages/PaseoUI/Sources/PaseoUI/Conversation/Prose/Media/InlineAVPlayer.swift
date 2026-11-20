#if canImport(UIKit)
import AVFoundation
import AVKit
import PaseoStore
import SwiftUI
import UIKit

/// Inline AVKit: native transport controls, PiP and full screen come only from AVKit.
struct InlineAVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
#endif
