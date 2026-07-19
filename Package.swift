// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLimitBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "codex-limit-bar", targets: ["CodexLimitBar"]),
    ],
    targets: [
        .target(name: "CodexLimitCore"),
        .executableTarget(
            name: "CodexLimitBar",
            dependencies: ["CodexLimitCore"]
        ),
        .testTarget(
            name: "CodexLimitCoreTests",
            dependencies: ["CodexLimitCore"]
        ),
    ]
)
