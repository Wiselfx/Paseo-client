// features: F01 F05 F10 F12  // hit: H28
// Fixture: store writes without compare, main-actor I/O, unbounded stream, force unwrap.
import Foundation

@MainActor @Observable final class BadStore {
    var status: String = ""
    var items: [Item] = []

    func handle(_ update: Update) {
        status = update.status // hit: H16
        items.sort { $0.id < $1.id } // hit: H16
        try? data.write(to: url) // hit: H17
        let blob = try? Data(contentsOf: url) // hit: H17
        let first = table["a"]! // expect: C30
    }

    func stream() {
        let pair = AsyncStream<Int>.makeStream(bufferingPolicy: .unbounded) // hit: H18
    }
}
