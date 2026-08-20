// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPSync",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPSync", targets: ["NSPSync"])
    ],
    dependencies: [
        .package(path: "../NSPCore"),
        .package(path: "../NSPPersistence"),
        .package(path: "../NSPPolicy"),
        .package(path: "../NSPTransfer"),
    ],
    targets: [
        .target(
            name: "NSPSync",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore"),
                .product(name: "NSPPersistence", package: "NSPPersistence"),
                .product(name: "NSPPolicy", package: "NSPPolicy"),
                .product(name: "NSPTransfer", package: "NSPTransfer"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPSyncTests",
            dependencies: ["NSPSync"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
