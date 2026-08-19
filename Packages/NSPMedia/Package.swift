// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPMedia",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPMedia", targets: ["NSPMedia"])
    ],
    dependencies: [
        .package(path: "../NSPPersistence"),
        .package(path: "../NSPPolicy"),
    ],
    targets: [
        .target(
            name: "NSPMedia",
            dependencies: [
                .product(name: "NSPPersistence", package: "NSPPersistence"),
                .product(name: "NSPPolicy", package: "NSPPolicy"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPMediaTests",
            dependencies: ["NSPMedia"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
