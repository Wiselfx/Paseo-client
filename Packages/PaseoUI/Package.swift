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
    ],
    targets: [
        .target(
            name: "PaseoUI",
            dependencies: [
                .product(name: "PaseoStore", package: "PaseoCore"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
            ],
            resources: [.process("Resources")]),
        .testTarget(name: "PaseoUITests", dependencies: ["PaseoUI"]),
    ])
