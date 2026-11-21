#if canImport(UIKit)
import PaseoStore
import Foundation

/// One URL the daemon advertises for a running service. Follows upstream's COMPAT split:
/// `localProxyUrl` (or a loopback-looking `proxyUrl`) is "Memorable", `publicProxyUrl` (or a
/// non-loopback `proxyUrl`) is "Reverse proxy", and `port` yields the direct URL. Deduped by
/// URL, and shown only when the script is a running service.
struct ScriptURLTarget: Identifiable {
    let kind: String
    let title: String
    let url: String
    let hostLabel: String
    var id: String { kind }

    static func targets(for script: WorkspaceScript) -> [ScriptURLTarget] {
        guard script.type == .service, script.lifecycle == .running else { return [] }
        func isLoopbackURL(_ url: String) -> Bool {
            guard let host = URLComponents(string: url)?.host?.lowercased() else { return true }
            return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        }
        var targets: [ScriptURLTarget] = []
        func add(_ kind: String, title: String, url: String?) {
            guard let url, !url.isEmpty, !targets.contains(where: { $0.url == url }) else { return }
            let host = URLComponents(string: url)?.host ?? url
            targets.append(ScriptURLTarget(kind: kind, title: title, url: url, hostLabel: host))
        }
        let local = script.localProxyUrl
            ?? (script.proxyUrl.map(isLoopbackURL) == true ? script.proxyUrl : nil)
        let pub = script.publicProxyUrl
            ?? (script.proxyUrl.map { !isLoopbackURL($0) } == true ? script.proxyUrl : nil)
        add("public", title: "Reverse proxy", url: pub)
        add("paseo", title: "Memorable", url: local)
        // No connection info on this client to build a true direct URL; localhost is the
        // honest default (matches upstream when there is no directTcp connection).
        if let port = script.port {
            add("direct", title: "Direct", url: "http://localhost:\(port)")
        }
        return targets
    }
}
#endif
