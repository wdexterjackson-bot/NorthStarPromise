// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPBackendClient",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPBackendClient", targets: ["NSPBackendClient"]),
    ],
    dependencies: [
        .package(path: "../NSPCore"),
        .package(path: "../NSPPolicy"),
    ],
    targets: [
        .target(
            name: "NSPBackendClient",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore"),
                .product(name: "NSPPolicy", package: "NSPPolicy"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPBackendClientTests",
            dependencies: ["NSPBackendClient"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
