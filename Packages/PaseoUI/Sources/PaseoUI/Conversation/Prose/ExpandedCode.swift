#if canImport(UIKit)
    struct ExpandedCode: Identifiable {
        let id = UUID()
        let language: String?
        let content: String
    }
#endif
