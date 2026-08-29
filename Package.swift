// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Steady",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Steady", targets: ["Steady"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .target(name: "PRMenubar", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "ClaudeUsage", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "ColorPickerKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "PortPilotKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "ClipboardKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Steady",
            dependencies: [
                "PRMenubar", "ClaudeUsage", "ColorPickerKit", "PortPilotKit", "ClipboardKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SteadyTests",
            dependencies: ["Steady"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
