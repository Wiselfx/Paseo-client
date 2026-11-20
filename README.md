# Paseo Client

A native SwiftUI client for [Paseo](https://github.com/getpaseo/paseo) on iPhone. Paseo runs your agents on your own machine through a daemon. This app connects to that daemon and shows its agents as chats.

<!-- screenshot: chat -->
![Chat with an agent](docs/images/chat.png)

The app needs iOS 26.0 or later and a Paseo daemon that you run. It reaches the daemon directly with the daemon password, or through the Paseo relay. The relay connection is end-to-end encrypted, and the host is paired by QR code or a pasted link.

Each agent is a chat made of turns. A turn holds your message, the agent's work steps, and its reply. Work steps fold into a summary you can open, and replies render as Markdown. You can dictate into the composer with on-device speech recognition, or use voice mode.

The sidebar groups workspaces by project and offers search, history and schedules. Scheduled runs can be created, paused and run once.

<!-- screenshot: sidebar and workspaces -->
![Sidebar and workspaces](docs/images/sidebar.png)

The workspace panel has Agents, Files, Changes and Terminal pages. Changes shows diffs and pull requests. Terminals and workspace scripts run on the daemon.

<!-- screenshot: workspace panel -->
![Workspace panel](docs/images/workspace-panel.png)

## Layout

| Path | What |
| --- | --- |
| `Packages/PaseoCore` | Protocol, connection and state. Foundation only, so its tests run on Linux. |
| `Packages/PaseoUI` | The SwiftUI design system and screens. Apple platforms only. |
| `App/` | The iOS app target: entry point, navigation, settings storage and Keychain. |
| `Tools/` | Scripts for capturing fixtures from a live daemon, style lint and the API audit. |
| `docs/` | Status, feature parity with Paseo, the UX spec and the work orders in `docs/tickets`. |

## Build and test

Core tests, on Linux or macOS with Swift 6.2 or later:

```sh
cd Packages/PaseoCore
swift test
```

The app builds in Xcode on a Mac. Open `App/PaseoClient.xcodeproj` and run the `PaseoClient` scheme. The project is generated from `App/project.yml` with XcodeGen. After you change that file, run `cd App && xcodegen generate`.

## Docs

- [ARCHITECTURE.md](ARCHITECTURE.md): layers, rules and the reasons for them
- [docs/](docs): status, parity with Paseo and work orders

Paseo itself is the specification for this client: [getpaseo/paseo](https://github.com/getpaseo/paseo).

## License

MIT. See [LICENSE](LICENSE).
