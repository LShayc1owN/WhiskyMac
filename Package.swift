// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Whisk",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Whisk",
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [.process("Resources"), .copy("WhiskyMacSymbols.bundle")],
            swiftSettings: [.swiftLanguageMode(.v5), .define("WHISK_MAY_DEV")]
        ),
        .testTarget(
            name: "WhiskTests",
            dependencies: ["Whisk"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
