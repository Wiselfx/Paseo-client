// swift-tools-version: 6.2
// PaseoCore: everything below the UI. Foundation-only, so it builds and tests on Linux.
// Layering (enforced by target dependencies): PaseoProtocol <- PaseoKit <- PaseoStore.
import PackageDescription

let package = Package(
    name: "PaseoCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "PaseoProtocol", targets: ["PaseoProtocol"]),
        .library(name: "PaseoKit", targets: ["PaseoKit"]),
        .library(name: "PaseoStore", targets: ["PaseoStore"]),
    ],
    targets: [
        .target(name: "PaseoProtocol"),
        .target(name: "PaseoKit", dependencies: ["PaseoProtocol"]),
        .target(name: "PaseoStore", dependencies: ["PaseoKit", "PaseoProtocol"]),
        // Live smoke test against a running daemon: `swift run paseo-probe --help`.
        .executableTarget(name: "paseo-probe", dependencies: ["PaseoStore", "PaseoKit", "PaseoProtocol"]),
        // Captured daemon traffic shared by every test target. Test-only; never linked by the app.
        .target(name: "PaseoFixtures", path: "Tests/PaseoFixtures", resources: [.copy("Fixtures")]),
        .testTarget(name: "PaseoProtocolTests", dependencies: ["PaseoProtocol", "PaseoFixtures"]),
        .testTarget(name: "PaseoKitTests", dependencies: ["PaseoKit", "PaseoProtocol", "PaseoFixtures"]),
        .testTarget(
            name: "PaseoStoreTests", dependencies: ["PaseoStore", "PaseoKit", "PaseoProtocol", "PaseoFixtures"]),
    ]
)
