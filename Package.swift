// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sugrob",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sugrob", targets: ["Sugrob"]),
    ],
    targets: [
        // Pure simulation: no AppKit / Metal, fully unit-testable.
        .target(name: "SnowCore"),
        .executableTarget(
            name: "Sugrob",
            dependencies: ["SnowCore"]
        ),
        .testTarget(
            name: "SnowCoreTests",
            dependencies: ["SnowCore"]
        ),
    ]
)
