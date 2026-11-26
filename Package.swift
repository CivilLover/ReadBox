// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadBox",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ReadBox", targets: ["ReadBox"])
    ],
    targets: [
        .executableTarget(
            name: "ReadBox",
            path: "Sources/ReadBox",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "ReadBoxTests",
            dependencies: ["ReadBox"],
            path: "Tests/ReadBoxTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
