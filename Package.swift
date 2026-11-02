// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TVCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TVCompanionCore"),
        .executableTarget(name: "TVCompanion", dependencies: ["TVCompanionCore"]),
        .testTarget(name: "TVCompanionCoreTests", dependencies: ["TVCompanionCore"]),
    ]
)
