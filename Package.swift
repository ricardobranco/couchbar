// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Couchbar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CouchbarCore"),
        .executableTarget(name: "Couchbar", dependencies: ["CouchbarCore"]),
        .testTarget(name: "CouchbarCoreTests", dependencies: ["CouchbarCore"]),
    ]
)
