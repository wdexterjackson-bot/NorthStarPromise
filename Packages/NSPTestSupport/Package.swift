// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPTestSupport",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPTestSupport", targets: ["NSPTestSupport"]),
    ],
    dependencies: [
        .package(path: "../NSPCore"),
        .package(path: "../NSPPersistence"),
        .package(path: "../NSPMedia"),
        .package(path: "../NSPTransfer"),
        .package(path: "../NSPSync"),
        .package(path: "../NSPIntelligence"),
        .package(path: "../NSPPolicy"),
        .package(path: "../NSPBackendClient"),
        .package(path: "../NSPActions"),
    ],
    targets: [
        .target(
            name: "NSPTestSupport",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore"),
                .product(name: "NSPPersistence", package: "NSPPersistence"),
                .product(name: "NSPMedia", package: "NSPMedia"),
                .product(name: "NSPTransfer", package: "NSPTransfer"),
                .product(name: "NSPSync", package: "NSPSync"),
                .product(name: "NSPIntelligence", package: "NSPIntelligence"),
                .product(name: "NSPPolicy", package: "NSPPolicy"),
                .product(name: "NSPBackendClient", package: "NSPBackendClient"),
                .product(name: "NSPActions", package: "NSPActions"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPTestSupportTests",
            dependencies: ["NSPTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
