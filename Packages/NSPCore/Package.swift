// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPCore", targets: ["NSPCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NSPCore",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPCoreTests",
            dependencies: ["NSPCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
