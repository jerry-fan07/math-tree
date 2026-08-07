// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MathTree",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GraphCore", targets: ["GraphCore"]),
        .executable(name: "MathTree", targets: ["MathTree"]),
    ],
    targets: [
        // Model, validation, scoring. Zero third-party dependencies, by rule.
        .target(name: "GraphCore"),
        // SwiftUI + Metal app shell. Bundled into MathTree.app by Scripts/bundle-app.sh.
        .executableTarget(
            name: "MathTree",
            dependencies: ["GraphCore"],
            path: "App/MathTree"
        ),
        .testTarget(name: "GraphCoreTests", dependencies: ["GraphCore"]),
    ]
)
