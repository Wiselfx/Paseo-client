#if canImport(UIKit)
    import Foundation
    import os
    import QuartzCore

    /// The performance instrument (W1). **Off by default**: it exists only when the app is launched
    /// with `-paseo-perf`, and every entry point below is one load and one branch when it is off.
    ///
    /// It answers the questions a regression needs a number for, and prints them as ONE aggregated
    /// line per second of activity through `os.Logger` (category `perf`, subsystem
    /// `com.wiselfx.paseoclient`), so the gate's `applog` (newest 300 lines) holds a whole scenario:
    ///
    /// - frame pacing from a `CADisplayLink` (`PerfMonitor`): frames, hitches (a frame later than
    ///   1.5 budgets), dropped frames, worst frame, p50 / p95 / p99 interval;
    /// - main-thread stalls from a run-loop observer pair (wake to sleep, so layout and the Core
    ///   Animation commit are inside it): stalls over 8 ms, the longest, the busy share of the
    ///   window, and the spans that overlapped the stall;
    /// - `os_signpost` intervals (`begin` / `end` / `measure`) around the hot paths, counted per
    ///   window;
    /// - `body` evaluation counters per named view (`body(_:)`).
    ///
    /// Rules in `docs/perf/PERFORMANCE-RULES.md`; scenarios in `docs/perf/scenarios/`.
    public enum PaseoPerf {
        /// True only when launched with `-paseo-perf`. Read once.
        public static let enabled: Bool = ProcessInfo.processInfo.arguments.contains("-paseo-perf")

        static let subsystem = "com.wiselfx.paseoclient"
        static let log = Logger(subsystem: subsystem, category: "perf")
        private static let signposter = OSSignposter(subsystem: subsystem, category: "perf")

        // MARK: Start

        /// Starts the frame monitor and the stall watcher. Call once from the app's init; a no-op
        /// unless `-paseo-perf` was passed.
        public static func startIfRequested() {
            guard enabled else { return }
            Task { @MainActor in PerfMonitor.shared.start() }
        }

        // MARK: Marks

        /// Names what is happening (a drawer opening, a sheet presenting) so the window line that
        /// contains it says so, and a quiet window around it is still printed.
        public static func mark(_ name: StaticString) {
            guard enabled else { return }
            let label = name.description
            store.withLock { $0.marks.append(label) }
        }

        // MARK: Counters

        /// Counts one evaluation of a view's `body`: `let _ = PaseoPerf.body("TurnRow")` as the first
        /// line of the body. Free when off.
        @inline(__always)
        public static func body(_ name: StaticString) {
            guard enabled else { return }
            let label = name.description
            store.withLock { $0.bodies[label, default: 0] += 1 }
        }

        /// Counts an arbitrary event (a decode, a cache miss, a layout measure) per window.
        @inline(__always)
        public static func count(_ name: StaticString) {
            guard enabled else { return }
            let label = name.description
            store.withLock { $0.counts[label, default: 0] += 1 }
        }

        // MARK: Spans

        /// An open interval: a signpost plus a timer, so the window line carries count / total /
        /// max per name and a stall can name what ran inside it.
        public struct Span: Sendable {
            fileprivate let name: StaticString
            fileprivate let start: Double
            fileprivate let state: OSSignpostIntervalState
            fileprivate let onMain: Bool
        }

        /// Opens a span. Nil (and free) when the instrument is off.
        public static func begin(_ name: StaticString) -> Span? {
            guard enabled else { return nil }
            return Span(
                name: name, start: CACurrentMediaTime(),
                state: signposter.beginInterval(name), onMain: Thread.isMainThread)
        }

        /// Closes a span opened by `begin`.
        public static func end(_ span: Span?) {
            guard enabled, let span else { return }
            signposter.endInterval(span.name, span.state)
            let finished = CACurrentMediaTime()
            let label = span.name.description
            store.withLock { state in
                var stat = state.spans[label] ?? SpanStat()
                stat.add(finished - span.start)
                state.spans[label] = stat
                if span.onMain {
                    if state.recent.count >= 256 { state.recent.removeFirst(128) }
                    state.recent.append(
                        RecentSpan(name: label, start: span.start, end: finished))
                }
            }
        }

        /// Runs `work` inside a span.
        @inline(__always)
        public static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
            guard enabled else { return try work() }
            let span = begin(name)
            defer { end(span) }
            return try work()
        }

        // MARK: Shared state

        struct SpanStat: Sendable {
            var count = 0
            var total: Double = 0
            var max: Double = 0
            mutating func add(_ seconds: Double) {
                count += 1
                total += seconds
                if seconds > max { max = seconds }
            }
        }

        struct RecentSpan: Sendable {
            let name: String
            let start: Double
            let end: Double
        }

        struct State: Sendable {
            var bodies: [String: Int] = [:]
            var counts: [String: Int] = [:]
            var spans: [String: SpanStat] = [:]
            var marks: [String] = []
            var recent: [RecentSpan] = []
            var lastValues: [String: String] = [:]
        }

        static let store = OSAllocatedUnfairLock(initialState: State())

        /// Drains the window's counters (called once per window by the monitor).
        static func drain() -> State {
            store.withLock { state in
                let out = state
                state.bodies.removeAll(keepingCapacity: true)
                state.counts.removeAll(keepingCapacity: true)
                state.spans.removeAll(keepingCapacity: true)
                state.marks.removeAll(keepingCapacity: true)
                return out
            }
        }

        /// The main-thread spans that overlapped `[from, to]`, longest first.
        static func spans(overlapping from: Double, _ to: Double) -> [RecentSpan] {
            store.withLock { state in
                state.recent
                    .filter { $0.end > from && $0.start < to }
                    .sorted { ($0.end - $0.start) > ($1.end - $1.start) }
            }
        }
    }
#endif
