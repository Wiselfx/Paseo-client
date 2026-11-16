// features: F01 F05 F10 F11 F12
// Fixture: GOOD store shapes: write only on change, sort into a copy, encode and write on a serial queue,
// a bounded stream.
import Foundation

@MainActor @Observable final class GoodStore {
    var status: String = ""
    var items: [Item] = []
    private let decoder = JSONDecoder()

    func handle(_ update: Update) {
        if status != update.status { status = update.status }
        var sorted = update.items
        sorted.sort { $0.id < $1.id }
        if items != sorted { items = sorted }
    }

    func stream() {
        let pair = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(64))
    }
}

private final class GoodWriter: Sendable {
    private let queue = DispatchQueue(label: "good.write", qos: .utility)

    func write(_ data: Data, to url: URL) {
        queue.async { try? data.write(to: url, options: .atomic) }
    }
}
