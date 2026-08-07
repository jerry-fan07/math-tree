// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MathTree",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GraphCore", targets: ["GraphCore"]),
        .executable(name: "ContentBuild", targets: ["ContentBuild"]),
        .executable(name: "MathTree", targets: ["MathTree"]),
    ],
    dependencies: [
        // Tooling only. The app never parses YAML — it consumes compiled JSON
        // (ground rule 3).
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        // Model, validation, scoring. Zero third-party dependencies, by rule.
        .target(name: "GraphCore"),
        // Content compiler: YAML → graph.json + deterministic layout.
        .executableTarget(
            name: "ContentBuild",
            dependencies: ["GraphCore", .product(name: "Yams", package: "Yams")]
        ),
        // SwiftUI + Metal app shell. Bundled into MathTree.app by Scripts/bundle-app.sh.
        .executableTarget(
            name: "MathTree",
            dependencies: ["GraphCore"],
            path: "App/MathTree"
        ),
        .testTarget(
            name: "GraphCoreTests",
            dependencies: ["GraphCore"],
            // FSRS vectors generated from the reference implementation before the
            // Swift port was written — see the Phase 5 decision log.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ContentBuildTests",
            dependencies: ["ContentBuild", "GraphCore"]
        ),
    ]
)
