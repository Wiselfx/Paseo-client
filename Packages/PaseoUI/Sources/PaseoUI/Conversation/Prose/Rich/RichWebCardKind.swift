#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - HTML artifact cards (V2: html fences)

/// Which document a web card hosts: an ordinary ` ```html ` fence, a full document when
/// the source is one.
enum RichWebCardKind: Equatable {
    case html

    /// The card header. The artifact page titles an html document from its own
    /// `<title>`/`<h1>`, falling back to "HTML".
    var title: String {
        switch self {
        case .html: "HTML"
        }
    }

    /// The cache namespace and the artifact-page kind.
    var contentKey: String {
        switch self {
        case .html: "html"
        }
    }
}
#endif
