// swift-tools-version: 6.2
// PaseoUI: SwiftUI. Apple platforms only; build in Xcode.
// Features depend on PaseoStore + DesignSystem, never on each other. The App composes them.
import PackageDescription

let package = Package(
    name: "PaseoUI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "HostsFeature", targets: ["HostsFeature"]),
        .library(name: "AgentsFeature", targets: ["AgentsFeature"]),
        .library(name: "ConversationFeature", targets: ["ConversationFeature"]),
    ],
    dependencies: [
        .package(path: "../PaseoCore"),
        .package(path: "../ClaudeUI"),
    ],
    targets: [
        // Look and feel. No Paseo types: everything here could render any chat app.
        .target(name: "DesignSystem", dependencies: [.product(name: "ClaudeUI", package: "ClaudeUI")]),
        .target(name: "HostsFeature", dependencies: ["DesignSystem"]),
        .target(
            name: "AgentsFeature",
            dependencies: ["DesignSystem", .product(name: "PaseoStore", package: "PaseoCore")]),
        .target(
            name: "ConversationFeature",
            dependencies: ["DesignSystem", .product(name: "PaseoStore", package: "PaseoCore")]),
    ]
)
