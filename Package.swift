// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickTranslate",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "QuickTranslate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
