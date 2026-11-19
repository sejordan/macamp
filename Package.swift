// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macamp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MacampCore",
            resources: [
                .embedInCode("Resources/Skins/Phosphor.json"),
                .embedInCode("Resources/Skins/RackUnit.json"),
                .embedInCode("Resources/Skins/NativeMini.json"),
                .embedInCode("Resources/SKIN_GUIDE.md"),
                .embedInCode("Resources/skin.schema.json"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "macamp",
            dependencies: ["MacampCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "macampTests",
            dependencies: ["macamp", "MacampCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacampCoreTests",
            dependencies: ["MacampCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
