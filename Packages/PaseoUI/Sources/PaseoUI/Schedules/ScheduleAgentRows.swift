#if canImport(UIKit)
import SwiftUI

/// The editor's Agent rows: provider, model, mode and thinking, each showing its current value
/// and pushing its picker through `picker`.
struct ScheduleAgentRows: View {
    let providerValue: String
    let modelValue: String
    let modeValue: String
    let thinkingValue: String
    @Binding var picker: ScheduleEditorPage.Picker?

    var body: some View {
        ListRow(
            title: "Provider",
            accessory: ListRow.Accessory.value(providerValue),
            action: {
                picker = .provider
            }
        )
        .panelRow()
        ListRow(
            title: "Model",
            accessory: ListRow.Accessory.value(modelValue),
            action: {
                picker = .model
            }
        )
        .panelRow()
        ListRow(
            title: "Mode",
            accessory: ListRow.Accessory.value(modeValue),
            action: {
                picker = .mode
            }
        )
        .panelRow()
        ListRow(
            title: "Thinking",
            accessory: ListRow.Accessory.value(thinkingValue),
            action: {
                picker = .thinking
            }
        )
        .panelRow()
    }
}
#endif
