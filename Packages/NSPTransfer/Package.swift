// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NSPTransfer",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "NSPTransfer", targets: ["NSPTransfer"])
    ],
    dependencies: [
        .package(path: "../NSPMedia")
    ],
    targets: [
        .target(
            name: "NSPTransfer",
            dependencies: [
                .product(name: "NSPMedia", package: "NSPMedia")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NSPTransferTests",
            dependencies: ["NSPTransfer"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
