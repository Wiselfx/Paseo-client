// swift-tools-version: 6.2
import PackageDescription

// PaseoUI: the app's SwiftUI layer. Apple platforms only; build in Xcode.
// One module: the ClaudeUI parts bin plus the Paseo screens built on it.
let package = Package(
    name: "PaseoUI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "PaseoUI", targets: ["PaseoUI"])
    ],
    dependencies: [
        .package(path: "../PaseoCore"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift.git", from: "3.1.0"),
        // Unreleased main: its iOS renderer rebuilds far fewer rows per TUI frame than 1.99.3.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", revision: "56d5cb3961306ecebae63ad208c6bb1ca1339bc2"),
    ],
    targets: [
        .target(
            name: "PaseoUI",
            dependencies: [
                .product(name: "PaseoStore", package: "PaseoCore"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [.process("Resources")]),
        // The transcript harness (TranscriptHarnessTests) builds a conversation through the real store
        // path, so it reaches the Core products PaseoUI itself is built on.
        .testTarget(
            name: "PaseoUITests",
            dependencies: [
                "PaseoUI",
                .product(name: "PaseoStore", package: "PaseoCore"),
                .product(name: "PaseoKit", package: "PaseoCore"),
                .product(name: "PaseoProtocol", package: "PaseoCore"),
            ]),
    ])
