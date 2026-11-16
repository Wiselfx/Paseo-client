// features: F01 F03 F04 F05 F06 F08
// Fixture: GOOD composer shapes from this repo: lazy holder, text read in the child's own body, static let
// for a system answer, idempotent updateUIView, cached pasteboard state, cancellable task loop.
import SwiftUI
import UIKit

@MainActor
final class GoodHolder {
    private let make: () -> GoodController
    private var built: GoodController?
    init(make: @escaping () -> GoodController) { self.make = make }
    var controller: GoodController {
        if let built { return built }
        let controller = withObservationTracking({ make() }, onChange: {})
        built = controller
        return controller
    }
}

struct GoodComposer: View {
    let store: ConversationStore
    @State private var holder: GoodHolder

    private static let cameraIsAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    init(store: ConversationStore) {
        self.store = store
        _holder = State(initialValue: GoodHolder { GoodController(store: store) })
    }

    private var text: String { store.draft }
    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { store.draft = $0 })
    }

    var body: some View {
        let _ = PaseoPerf.body("GoodComposer")
        GoodField(text: textBinding)
            .task(id: store.agentId) { await poll() }
    }

    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            holder.controller.tick()
        }
    }
}

struct GoodField: UIViewRepresentable, Equatable {
    @Binding var text: String

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    func makeUIView(context: Context) -> UITextView { UITextView() }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
    }
}
