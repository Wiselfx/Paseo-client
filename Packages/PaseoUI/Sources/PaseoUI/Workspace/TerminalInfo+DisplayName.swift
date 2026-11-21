#if canImport(UIKit)
import PaseoStore

extension TerminalInfo {
    /// The tab label: the shell's own title when it set a distinct one, else the daemon's name.
    var displayName: String {
        if let title, !title.isEmpty, title != name {
            return title
        }
        return name
    }
}
#endif
