#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// YouTube oEmbed titles, by video id. Small strings; a plain bounded table is enough.
@MainActor
enum YouTubeTitleCache {
    private struct Entry {
        var title: String
        var channel: String?
    }

    private static var table: [String: Entry] = [:]

    static func entry(for id: String) -> (title: String, channel: String?)? {
        table[id].map { ($0.title, $0.channel) }
    }

    static func store(title: String, channel: String?, for id: String) {
        if table.count >= 128 { table.removeAll(keepingCapacity: true) }
        table[id] = Entry(title: title, channel: channel)
    }
}
#endif
