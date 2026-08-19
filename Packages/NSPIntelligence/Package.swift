// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPIntelligence",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPIntelligence", targets: ["NSPIntelligence"]),
    ],
    dependencies: [
        .package(path: "../NSPSync"),
    ],
    targets: [
        .target(
            name: "NSPIntelligence",
            dependencies: [
                .product(name: "NSPSync", package: "NSPSync"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPIntelligenceTests",
            dependencies: ["NSPIntelligence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
