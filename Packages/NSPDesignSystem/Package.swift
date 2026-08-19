// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPDesignSystem",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPDesignSystem", targets: ["NSPDesignSystem"]),
    ],
    dependencies: [
        .package(path: "../NSPCore"),
    ],
    targets: [
        .target(
            name: "NSPDesignSystem",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPDesignSystemTests",
            dependencies: ["NSPDesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
