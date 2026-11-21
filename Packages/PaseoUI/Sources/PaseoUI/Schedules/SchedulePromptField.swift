#if canImport(UIKit)
import SwiftUI

/// The editor's prompt field: a vertical `TextField` that starts five lines tall and grows with
/// the text and Dynamic Type. The focus binding lets the keyboard's Done button dismiss it.
struct SchedulePromptField: View {
    @Binding var prompt: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField("What should the agent do each time?", text: $prompt, axis: .vertical)
            .lineLimit(5...)
            .font(.paseo(.callout))
            .focused(isFocused)
            .padding(Space.lg)
            .accessibilityIdentifier("schedule.prompt")
    }
}
#endif
