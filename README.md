# Paseo Client

A native iPhone app for the [Paseo](https://github.com/getpaseo/paseo) daemon: your agents run
on your machine, and you talk to them in an app that feels like Messages, with the turn-by-turn
feel of Claude for iOS.

Personal project, work in progress.

- [ARCHITECTURE.md](ARCHITECTURE.md): layers, rules, and why
- [AGENTS.md](AGENTS.md): rules for coding agents
- [docs/tickets](docs/tickets): work orders

## Layout

| Path | What |
| --- | --- |
| `Packages/PaseoCore` | Protocol, connection and state. Foundation only; `swift test` runs on Linux. |
| `Packages/PaseoUI` | SwiftUI design system and features (coming). |
| `App/` | The iOS app target (coming). |
| `Packages/ClaudeUI` | The [claude-ios-ui](https://github.com/bryanrg22/claude-ios-ui) package this repo was forked from, kept as a parts bin. |
| `Tools/` | Fixture capture from a live daemon. |

## Develop

```sh
cd Packages/PaseoCore && swift test
```
