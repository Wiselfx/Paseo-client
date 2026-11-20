#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Hands the model, the cell environment and the bars' insets to the engine.
struct TranscriptCollectionHost: UIViewRepresentable {
    let engine: TranscriptEngine
    let store: ConversationStore
    let controller: ChatController
    let model: TranscriptModel
    let environment: TranscriptCellEnvironment
    let insets: EdgeInsets

    func makeUIView(context: Context) -> TranscriptContainerView {
        engine.attach(store: store, controller: controller)
        return engine.container
    }

    func updateUIView(_ uiView: TranscriptContainerView, context: Context) {
        engine.update(model: model, environment: environment)
        engine.setInsets(insets, animation: context.transaction.animation)
    }
}
#endif
