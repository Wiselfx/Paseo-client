#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// The two boxes a web card reserves before its page has measured itself, and the smallest
/// height a measured page may take. One settle per card, then never again.
enum WebCardMetrics {
    static let reservedHeight: CGFloat = 240
    static let minimumHeight: CGFloat = 80
}
#endif
