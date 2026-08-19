// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPPersistence",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPPersistence", targets: ["NSPPersistence"])
    ],
    dependencies: [
        .package(path: "../NSPCore")
    ],
    targets: [
        .target(
            name: "NSPPersistence",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPPersistenceTests",
            dependencies: ["NSPPersistence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
