// features: F02 F05 F06 F09 F12 F14 F17 F19
// Fixture for final-check --self-test. BAD code on purpose: every `expect:` / `hit:` marker is asserted exactly.
import SwiftUI

struct BadTurnRow: View { // hit: H03
    let seqEnd: Int
    let text: String
    let items: [Item]
    let onTap: () -> Void // expect: C06
    let onOpen: (String) -> Void // expect: C06
    @State private var engine = VoiceAudioEngine() // expect: C04

    init(session: HostSession, store: ConversationStore) {
        _holder = State(initialValue: ChatController(session: session)) // expect: C04
        self._text = Binding(get: { store.draft }, set: { store.draft = $0 }) // expect: C03
    }

    var body: some View {
        let formatter = DateFormatter() // expect: C08
        let data = try? Data(contentsOf: url) // expect: C09
        let calendar = Calendar.current // hit: H06
        let sorted = store.turns.sorted { $0.a < $1.a } // hit: H05
        let binding = Binding(get: { store.draft }, set: { _ in }) // hit: H02
        VStack {
            Text(text).id("row:\(seqEnd)") // expect: C01
            Text(text).id(UUID()) // expect: C01
            Text(text).id(someValue) // hit: H01
            ForEach(items, id: \.self) { item in // hit: H01
                GeometryReader { proxy in // expect: C13
                    Color.clear
                }
            }
            GeometryReader { proxy in // hit: H07
                Color.clear
            }
            ForEach(session.agents.filter { $0.active }) { agent in // hit: H05
                Text(agent.title)
            }
            AnyView(Text("x")) // hit: H04
            Text("shadow").shadow(radius: 2) // hit: H20
            Text("fx").drawingGroup() // hit: H20
        }
        .onAppear { Task { await load() } } // expect: C15
        .task { await load() } // hit: H09
        .onChange(of: items.filter { $0.done }) { _, _ in } // expect: C19
        .onChange(of: session.agents) { _, _ in } // hit: H11
        .onChange(of: items.map(\.id)) { _, _ in } // hit: H11
        .environment(\.openAction, { value in handle(value) }) // hit: H25
        .gesture(DragGesture()) // hit: H26
        withAnimation { flag.toggle() } // expect: C21
        let timer = Timer.publish(every: 1, on: .main, in: .common) // hit: H10
        DispatchQueue.main.async { flag = true } // hit: H08
        print("rendered") // expect: C28
        let _ = PaseoPerf.diff("row", [("a", "b")]) // expect: C27
        let count = value!.count // expect: C30
        let tail = items[idx...].count // expect: C47
        proxy.scrollTo("bottom") // hit: H27
    }

    static let windowSize = 8 // expect: C44 // hit: H27

    func repinOpen() {
        scrollPosition.scrollTo(edge: .bottom) // expect: C44 // hit: H27
        layer.shouldRasterize = true // expect: C44
    }

    func spin() {
        while true { // expect: C17
            work()
        }
    }
}

final class OldModel: ObservableObject { // expect: C45
    @Published var count = 0 // expect: C45
}
