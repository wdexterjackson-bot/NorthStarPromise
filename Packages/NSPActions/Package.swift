// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPActions",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPActions", targets: ["NSPActions"])
    ],
    dependencies: [
        .package(path: "../NSPIntelligence"),
        .package(path: "../NSPPolicy"),
    ],
    targets: [
        .target(
            name: "NSPActions",
            dependencies: [
                .product(name: "NSPIntelligence", package: "NSPIntelligence"),
                .product(name: "NSPPolicy", package: "NSPPolicy"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPActionsTests",
            dependencies: ["NSPActions"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
