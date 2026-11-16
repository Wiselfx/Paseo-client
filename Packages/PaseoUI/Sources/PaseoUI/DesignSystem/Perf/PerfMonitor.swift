#if canImport(UIKit)
    import Foundation
    import QuartzCore
    import UIKit

    /// Frame pacing and main-thread stalls, aggregated into one log line per window (W1).
    ///
    /// Frames come from a `CADisplayLink` on the main run loop (common modes, so scrolling does not
    /// pause it). A *hitch* is a frame that arrived later than 1.5 budgets (at least one frame
    /// dropped); the budget is the display link's own frame duration (16.7 ms on a 60 Hz display, 8.3
    /// ms at 120 Hz), never a hard-coded number.
    ///
    /// Stalls come from a pair of run-loop observers: one at wake-up, one after Core Animation's own
    /// commit observer, so the measured stretch is everything the main thread did for one wake: the
    /// source callbacks, SwiftUI's update, layout and the commit. Over `stallThreshold` it counts as
    /// a stall and names the signpost spans that overlapped it.
    ///
    /// A window that holds activity (scroll in tracking mode, a `PaseoPerf.mark`, a hitch or a stall)
    /// is printed; quiet windows are not, so an idle app does not push a scenario out of the gate's
    /// 300-line `applog` tail.
    @MainActor
    final class PerfMonitor: NSObject {
        static let shared = PerfMonitor()

        /// Main-thread work per wake that counts as a stall (the ticket's 8 ms).
        static let stallThreshold: Double = 0.008
        /// One log line per this many seconds of frames.
        static let windowSeconds: Double = 1.0

        private var link: CADisplayLink?
        private var started = false
        private var launchedAt = CACurrentMediaTime()

        // Frame accumulators for the open window.
        private var windowStart: Double = 0
        private var lastTimestamp: Double = 0
        private var intervals: [Double] = []
        private var budgetSum: Double = 0
        private var hitches = 0
        private var dropped = 0
        private var hitchSeconds: Double = 0
        private var worst: Double = 0
        private var longestGap = 0
        private var trackingFrames = 0

        // Stall accumulators for the open window.
        private var wakeAt: Double = 0
        private var busySeconds: Double = 0
        private var stalls = 0
        private var stallWorst: Double = 0
        private var stallNotes: [String] = []
        private var wakes = 0

        private var windowsPrinted = 0
        private var observers: [CFRunLoopObserver] = []

        func start() {
            guard !started else { return }
            started = true
            launchedAt = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
            installObservers()
            #if arch(arm64)
                // The sampler suspends the main thread a thousand times a second while it is busy, which
                // is enough to change what a timing-sensitive layout does (a long chat opened blank with
                // it running and not without), so it is a second switch: `-paseo-perf-sample`.
                if ProcessInfo.processInfo.arguments.contains("-paseo-perf-sample") {
                    PerfSampler.shared.start()
                }
            #endif
            #if targetEnvironment(simulator)
                let target = "sim"
            #else
                let target = "device"
            #endif
            PaseoPerf.log.notice("perf start target=\(target, privacy: .public)")
        }

        // MARK: Run-loop observers

        private func installObservers() {
            let main = CFRunLoopGetMain()
            // Wake-up: first in line, so the stretch starts as early as the loop's own work.
            let wake = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, Int.min
            ) { _, _ in
                MainActor.assumeIsolated { PerfMonitor.shared.didWake() }
            }
            // Sleep: after Core Animation's commit observer (order 2,000,000), so layout and the
            // commit are inside the measured stretch.
            let sleep = CFRunLoopObserverCreateWithHandler(
                kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max
            ) { _, _ in
                MainActor.assumeIsolated { PerfMonitor.shared.willSleep() }
            }
            for observer in [wake, sleep] {
                guard let observer else { continue }
                CFRunLoopAddObserver(main, observer, .commonModes)
                observers.append(observer)
            }
        }

        private func didWake() {
            wakeAt = CACurrentMediaTime()
            #if arch(arm64)
                PerfSampler.shared.markBusy(wakeAt)
            #endif
        }

        private func willSleep() {
            guard wakeAt > 0 else { return }
            let now = CACurrentMediaTime()
            let busy = now - wakeAt
            let began = wakeAt
            wakeAt = 0
            #if arch(arm64)
                PerfSampler.shared.markBusy(0)
            #endif
            busySeconds += busy
            wakes += 1
            guard busy >= Self.stallThreshold else { return }
            stalls += 1
            if busy > stallWorst { stallWorst = busy }
            guard stallNotes.count < 4 else { return }
            let inside = PaseoPerf.spans(overlapping: began, now).prefix(2)
                .map { "\($0.name) \(Self.ms($0.end - $0.start))" }
            let note = Self.ms(busy) + (inside.isEmpty ? "" : "[" + inside.joined(separator: ",") + "]")
            stallNotes.append(note)
        }

        // MARK: Frames

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            let budget = max(link.targetTimestamp - link.timestamp, 0.001)
            if windowStart == 0 {
                windowStart = now
                PaseoPerf.log.notice("perf budget=\(Self.ms(budget), privacy: .public)ms")
            }
            if lastTimestamp > 0 {
                let delta = now - lastTimestamp
                // A gap over a second is the app leaving the foreground, not a frame.
                if delta < 1.0 {
                    intervals.append(delta)
                    budgetSum += budget
                    if delta > worst { worst = delta }
                    if delta > budget * 1.5 {
                        let missed = max(Int((delta / budget).rounded()) - 1, 1)
                        hitches += 1
                        dropped += missed
                        hitchSeconds += delta - budget
                        if missed > longestGap { longestGap = missed }
                    }
                }
            }
            lastTimestamp = now
            if let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()),
                (mode.rawValue as String) == "UITrackingRunLoopMode"
            {
                trackingFrames += 1
            }
            if now - windowStart >= Self.windowSeconds { flush(at: now) }
        }

        private func flush(at now: Double) {
            let drained = PaseoPerf.drain()
            defer { reset(at: now) }
            guard !intervals.isEmpty else { return }
            let interesting =
                trackingFrames > 0 || hitches > 0 || stalls > 0 || !drained.marks.isEmpty
            guard interesting else { return }

            let sorted = intervals.sorted()
            func percentile(_ p: Double) -> Double {
                sorted[min(Int(Double(sorted.count - 1) * p), sorted.count - 1)]
            }
            let windowLength = max(now - windowStart, 0.001)
            var parts: [String] = []
            parts.append("t=\(Self.seconds(now - launchedAt))")
            parts.append("fr=\(intervals.count)")
            parts.append("hit=\(hitches)")
            parts.append("drop=\(dropped)")
            parts.append("gap=\(longestGap)")
            parts.append("hms=\(Self.ms(hitchSeconds))")
            parts.append("worst=\(Self.ms(worst))")
            parts.append("p50=\(Self.ms(percentile(0.5)))")
            parts.append("p95=\(Self.ms(percentile(0.95)))")
            parts.append("p99=\(Self.ms(percentile(0.99)))")
            parts.append("scroll=\(trackingFrames)")
            parts.append("busy=\(Int((busySeconds / windowLength * 100).rounded()))%")
            parts.append("stall8=\(stalls)")
            parts.append("smax=\(Self.ms(stallWorst))")
            if !stallNotes.isEmpty { parts.append("stalls=" + stallNotes.joined(separator: ";")) }
            if !drained.marks.isEmpty {
                parts.append("mark=" + drained.marks.joined(separator: ","))
            }
            if !drained.bodies.isEmpty { parts.append("body=" + Self.pairs(drained.bodies)) }
            if !drained.counts.isEmpty { parts.append("n=" + Self.pairs(drained.counts)) }
            if !drained.spans.isEmpty {
                let spans = drained.spans.sorted { $0.value.total > $1.value.total }.prefix(6)
                    .map {
                        "\($0.key):\($0.value.count)x\(Self.ms($0.value.total))/max\(Self.ms($0.value.max))"
                    }
                parts.append("sp=" + spans.joined(separator: ","))
            }
            let line = parts.joined(separator: " ")
            windowsPrinted += 1
            PaseoPerf.log.notice("perf \(line, privacy: .public)")
            #if arch(arm64)
                // A second line, because the system truncates one dynamic string at 1 KB.
                let histogram = PerfSampler.shared.drain()
                if histogram.samples > 0 {
                    func top(_ table: [String: Int]) -> String {
                        table.sorted { $0.value > $1.value }.prefix(4)
                            .map { "\($0.key):\($0.value)" }.joined(separator: " | ")
                    }
                    let hot =
                        "t=\(Self.seconds(now - launchedAt)) samples=\(histogram.samples) own=\(top(histogram.own)) leaf=\(top(histogram.leaf))"
                    PaseoPerf.log.notice("perf.hot \(hot, privacy: .public)")
                }
            #endif
        }

        private func reset(at now: Double) {
            windowStart = now
            intervals.removeAll(keepingCapacity: true)
            budgetSum = 0
            hitches = 0
            dropped = 0
            hitchSeconds = 0
            worst = 0
            longestGap = 0
            trackingFrames = 0
            busySeconds = 0
            stalls = 0
            stallWorst = 0
            stallNotes.removeAll(keepingCapacity: true)
            wakes = 0
        }

        // MARK: Formatting

        private static func ms(_ seconds: Double) -> String {
            String(format: "%.1f", seconds * 1000)
        }

        private static func seconds(_ value: Double) -> String {
            String(format: "%.1f", value)
        }

        private static func pairs(_ counts: [String: Int]) -> String {
            counts.sorted { $0.value > $1.value }.prefix(16)
                .map { "\($0.key):\($0.value)" }.joined(separator: ",")
        }
    }
#endif
