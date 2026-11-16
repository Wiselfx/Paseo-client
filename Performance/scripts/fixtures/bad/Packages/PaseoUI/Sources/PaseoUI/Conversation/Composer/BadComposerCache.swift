// features: F02 F03 F04 F05 F07 F08 F13
// Fixture: caches, representables, lists and web views that need a human answer.
import SwiftUI
import UIKit
import WebKit

final class BadThumbs {
    private let cache = NSCache<NSString, UIImage>() // expect: C20
    private var thumbnailCache: [String: UIImage] = [:] // hit: H12
    static var shared: [String: Int] = [:] // hit: H12
    private var loader = Task { await run() } // hit: H09
}

final class Racy: @unchecked Sendable { // hit: H24
    var value = 0
}

struct BadField: UIViewRepresentable { // hit: H15
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView { UITextView() }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text // hit: H15
        uiView.font = font // hit: H15
    }
}

struct BadList: View {
    let items: [Item]
    var body: some View {
        ScrollView { // hit: H19
            VStack {
                ForEach(items) { item in
                    Text(item.name)
                }
            }
        }
    }
}

func makeWeb() -> WKWebView {
    WKWebView(frame: .zero) // hit: H22
}
