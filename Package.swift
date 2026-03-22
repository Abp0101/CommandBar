// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CommandBar",
            path: "Sources/CommandBar"
        )
    ]
)
