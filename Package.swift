// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ByteTrail",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ByteTrailCore", targets: ["ByteTrailCore"]),
        .executable(name: "ByteTrail", targets: ["ByteTrailApp"]),
        .executable(name: "ByteTrailVerification", targets: ["ByteTrailVerification"])
    ],
    targets: [
        .target(
            name: "ByteTrailCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ByteTrailApp",
            dependencies: ["ByteTrailCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ByteTrailCoreTests",
            dependencies: ["ByteTrailCore"]
        ),
        // This framework-free harness keeps the release-blocking checks available
        // even when XCTest cannot be launched by the current environment.
        .executableTarget(
            name: "ByteTrailVerification",
            dependencies: ["ByteTrailCore"]
        )
    ]
)
