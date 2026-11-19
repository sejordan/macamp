// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macamp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MacampCore",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "macamp",
            dependencies: ["MacampCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacampCoreTests",
            dependencies: ["MacampCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
