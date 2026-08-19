// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPPersistence",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPPersistence", targets: ["NSPPersistence"])
    ],
    dependencies: [
        .package(path: "../NSPCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "NSPPersistence",
            dependencies: [
                .product(name: "NSPCore", package: "NSPCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
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
