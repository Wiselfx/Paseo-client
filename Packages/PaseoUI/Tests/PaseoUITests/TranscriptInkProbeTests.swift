import Foundation
import PaseoKit
import PaseoProtocol
import PaseoStore
import SwiftUI
import UIKit
import XCTest

@testable import PaseoUI

/// Finds out which way of reading what a transcript cell draws works in the test host.
@MainActor
final class TranscriptInkProbeTests: XCTestCase {
    private var lines: [String] = []

    private func log(_ text: String) {
        lines.append(text)
        print("PROBE " + text)
    }

    func testProbe() async throws {
        let out = ProcessInfo.processInfo.environment["TRANSCRIPT_HARNESS_OUT"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let client = SyntheticDaemonClient(page: try SyntheticHistory.page(turns: 12))
        let session = HostSession(client: client)
        let store = session.conversation(for: SyntheticHistory.agentId)
        var waited = 0
        while store.phase != .ready && waited < 500 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        let controller = ChatController(session: session, store: store)
        let host = UIHostingController(rootView: TranscriptView(store: store, controller: controller))
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 103, left: 0, bottom: 94, right: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        var found: TranscriptCollectionView?
        var tries = 0
        while found == nil && tries < 300 {
            found = Self.find(in: window)
            if found == nil { try await Task.sleep(for: .milliseconds(10)) }
            tries += 1
        }
        let cv = try XCTUnwrap(found)
        try await Task.sleep(for: .seconds(2))
        // Scroll to a middle cell so one sits fully on screen.
        let engine = try XCTUnwrap(cv.engine)
        controller.isFollowing = false
        cv.contentOffset = CGPoint(x: 0, y: max(engine.minOffsetY, cv.contentOffset.y - 1500))
        try await Task.sleep(for: .seconds(1))

        log("window scene: \(String(describing: window.windowScene)), screen scale \(window.screen.scale)")
        log("visible cells: \(cv.visibleCells.count), offset \(cv.contentOffset.y)")
        for cell in cv.visibleCells.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            let screenY = cell.frame.minY - cv.contentOffset.y - 400
            log("cell \(cv.indexPath(for: cell)?.item ?? -1) screenY \(Int(screenY)) h \(Int(cell.bounds.height)) safe \(cell.contentView.safeAreaInsets) subviews \(cell.contentView.subviews.map { String(describing: type(of: $0)) })")
        }
        guard let cell = cv.visibleCells.filter({ $0.bounds.height < 900 }).sorted(by: { $0.frame.minY < $1.frame.minY }).first(where: {
            let y = $0.frame.minY - cv.contentOffset.y - 400
            return y > 0 && y < 400
        }) ?? cv.visibleCells.first
        else { throw XCTSkip("no cell") }
        log("probing cell \(cv.indexPath(for: cell)?.item ?? -1) height \(cell.bounds.height)")

        func count(_ image: UIImage) -> Int {
            guard let cg = image.cgImage else { return -1 }
            let w = cg.width, h = cg.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            var n = 0
            var i = 3
            while i < px.count { if px[i] > 24 { n += 1 }; i += 4 }
            return n
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = cell.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        for after in [false, true] {
            var ok = false
            let image = renderer.image { _ in ok = cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: after) }
            log("cell drawHierarchy afterScreenUpdates \(after): returned \(ok), inked px \(count(image))")
        }
        let layerImage = renderer.image { ctx in cell.layer.render(in: ctx.cgContext) }
        log("cell layer.render: inked px \(count(layerImage))")
        let cvRenderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        var okWindow = false
        let windowImage = cvRenderer.image { _ in okWindow = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
        log("window drawHierarchy: returned \(okWindow), inked px \(count(windowImage))")
        let windowLayer = cvRenderer.image { ctx in window.layer.render(in: ctx.cgContext) }
        log("window layer.render: inked px \(count(windowLayer))")
        let hostImage = cvRenderer.image { _ in _ = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        log("host view drawHierarchy after updates: inked px \(count(hostImage))")

        func dump(_ layer: CALayer, depth: Int) {
            guard depth < 7, lines.count < 400 else { return }
            let pad = String(repeating: " ", count: depth * 2)
            log("\(pad)\(type(of: layer)) frame \(layer.frame) contents \(layer.contents != nil) subs \(layer.sublayers?.count ?? 0) clips \(layer.masksToBounds)")
            for sub in (layer.sublayers ?? []).prefix(12) { dump(sub, depth: depth + 1) }
        }
        log("--- layer tree of the cell")
        dump(cell.layer, depth: 0)
        func dumpViews(_ view: UIView, depth: Int) {
            guard depth < 7, lines.count < 400 else { return }
            let pad = String(repeating: " ", count: depth * 2)
            log("\(pad)\(type(of: view)) frame \(view.frame) safe \(view.safeAreaInsets)")
            for sub in view.subviews.prefix(12) { dumpViews(sub, depth: depth + 1) }
        }
        log("--- view tree of the cell")
        dumpViews(cell, depth: 0)
        try lines.joined(separator: "\n").write(toFile: (out as NSString).appendingPathComponent("probe.txt"), atomically: true, encoding: .utf8)
        withExtendedLifetime(session) {}
    }

    private static func find(in view: UIView) -> TranscriptCollectionView? {
        if let found = view as? TranscriptCollectionView { return found }
        for sub in view.subviews { if let found = find(in: sub) { return found } }
        return nil
    }
}
