// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Quilland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuillandCore", targets: ["QuillandCore"]),
        .executable(name: "Quilland", targets: ["Quilland"]),
    ],
    targets: [
        // The formats, names, cache, snapshots, export and LM Studio client (proved in the spike).
        .target(name: "QuillandCore"),
        // Rewrites one file again and again until it is killed (the atomic-write tests).
        .executableTarget(name: "StressWriter", dependencies: ["QuillandCore"]),
        // The application (AppKit). Packaged as Quilland.app by make-app.sh.
        .executableTarget(
            name: "Quilland",
            dependencies: ["QuillandCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "QuillandCoreTests",
            dependencies: ["QuillandCore", "StressWriter"],
            resources: [.copy("Corpus")]
        ),
        .testTarget(
            name: "QuillandTests",
            dependencies: ["Quilland", "QuillandCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
