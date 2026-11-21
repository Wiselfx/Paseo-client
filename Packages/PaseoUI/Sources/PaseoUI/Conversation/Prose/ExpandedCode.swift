#if canImport(UIKit)
import Foundation

    struct ExpandedCode: Identifiable {
        let id = UUID()
        let language: String?
        let content: String

        /// The expanded sheet's title: the language with its first letter capitalised ("Swift code"),
        /// or plain "Code" for a fence without one. Localised inside the package's bundle.
        var title: String {
            guard let language else { return String(localized: "Code", bundle: #bundle) }
            let name = language.prefix(1).uppercased() + language.dropFirst()
            return String(localized: "\(name) code", bundle: #bundle)
        }
    }
#endif
