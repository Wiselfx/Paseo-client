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
        /// Counts an event named at run time (a measured value, an id). Free when off, but the name
        /// is built by the caller, so wrap the call in `if PaseoPerf.enabled`.
        static func countNamed(_ name: String) {
            guard enabled else { return }
            store.withLock { $0.counts[name, default: 0] += 1 }
        }

        /// A poor man's `_printChanges` that reaches the gate's log (W1): call it from a body with the
        /// view's inputs as strings; each input that differs from the previous call counts
        /// `diff.<prefix>.<key>`, and a call where none differ counts `diff.<prefix>.none` (the body
        /// ran because an observed store changed, not because an input did). Free when off: the
        /// values are an autoclosure.
        @inline(__always)
        static func diff(
            _ prefix: StaticString, _ values: @autoclosure () -> [(StaticString, String)]
        ) {
            guard enabled else { return }
            record(diff: prefix.description, values())
        }

        private static func record(diff prefix: String, _ values: [(StaticString, String)]) {
            store.withLock { state in
                var anyChanged = false
                for (key, value) in values {
                    let slot = prefix + "." + key.description
                    if let previous = state.lastValues[slot], previous != value {
                        state.counts["diff." + slot, default: 0] += 1
                        anyChanged = true
                    }
                    state.lastValues[slot] = value
                }
                if !anyChanged { state.counts["diff." + prefix + ".none", default: 0] += 1 }
            }
        }

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
