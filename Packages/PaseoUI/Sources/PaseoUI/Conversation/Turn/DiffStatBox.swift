#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// A boxed diff stat; `NSCache` only holds class values.
final class DiffStatBox {
    let added: Int
    let removed: Int

    init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }
}
#endif
