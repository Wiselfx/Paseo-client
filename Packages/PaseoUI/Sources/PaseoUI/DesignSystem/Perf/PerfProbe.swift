#if canImport(UIKit)
    import SwiftUI

    /// Counts how often one value a view depends on is re-read and how often it really changes
    /// (W1). Put it in a `.background` under `if PaseoPerf.enabled`; it draws nothing and, because
    /// it reads the value in its own body, it never adds a dependency to the view it sits behind.
    ///
    /// The window line shows `probe.<name>.read` (the body ran: something observed moved) and
    /// `probe.<name>.changed` (the value is different). A large `read` with a small `changed` is an
    /// observable that is written with equal values, which is the usual cause of an invalidation
    /// storm.
    public struct PerfProbe<Value: Equatable>: View {
        let name: StaticString
        let value: Value

        public init(_ name: StaticString, _ value: Value) {
            self.name = name
            self.value = value
        }

        public var body: some View {
            let _ = PaseoPerf.countRead(name)
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: value) { _, _ in PaseoPerf.countChange(name) }
        }
    }

    extension PaseoPerf {
        @inline(__always)
        static func countRead(_ name: StaticString) {
            guard enabled else { return }
            let label = "probe." + name.description + ".read"
            store.withLock { $0.counts[label, default: 0] += 1 }
        }

        @inline(__always)
        static func countChange(_ name: StaticString) {
            guard enabled else { return }
            let label = "probe." + name.description + ".changed"
            store.withLock { $0.counts[label, default: 0] += 1 }
        }
    }
#endif
