#if canImport(UIKit)
import Foundation

/// The forge setup step a host is missing, when the daemon reports it on the PR status payload
/// (`authState`). GitHub-only: the commands are gh-specific, and guessing another forge's
/// installer would be wrong. Copy-only; nothing is run remotely.
enum ForgeSetupIssue {
    case cliMissing
    case unauthenticated

    var title: String {
        switch self {
        case .cliMissing: "GitHub CLI isn't installed on this host"
        case .unauthenticated: "GitHub CLI isn't authenticated on this host"
        }
    }

    /// The commands to run on the host. `remoteHost` adds `--hostname` for Enterprise hosts.
    func commands(remoteHost: String?) -> [String] {
        switch self {
        case .cliMissing:
            return ["brew install gh", "sudo apt install gh", "gh auth login"]
        case .unauthenticated:
            if let remoteHost, remoteHost != "github.com" {
                return ["gh auth login --hostname \(remoteHost)"]
            }
            return ["gh auth login"]
        }
    }

    /// The hostname of a git remote URL (ssh, https or scp-style), or nil.
    static func host(ofRemote remote: String) -> String? {
        var s = remote
        for prefix in ["ssh://", "https://", "http://", "git@"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let end = s.firstIndex(where: { $0 == "/" || $0 == ":" }) {
            s = String(s[..<end])
        }
        let host = s.trimmingCharacters(in: .whitespaces)
        return host.isEmpty ? nil : host
    }
}
#endif
