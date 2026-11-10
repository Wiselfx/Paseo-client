#if canImport(UIKit)
import SwiftUI

/// One page in a sheet's stack: the inset-grouped list restyled onto the palette (PLAN §RE).
/// Shared by Settings, Schedules, History and Search, which all present lists the same way.
/// R-5: one component, not a copy per screen.
struct PageList<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }
}

extension View {
    /// A page row: the panel fill, with the row keeping its own inner padding.
    func panelRow(_ background: Color = Palette.panel) -> some View {
        listRowBackground(background)
            .listRowInsets(EdgeInsets())
    }

    /// A pushed page's chrome: inline title, palette background. A sheet root keeps its own title.
    func inlinePageTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Palette.background)
    }
}
#endif
