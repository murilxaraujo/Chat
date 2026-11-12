// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Chat",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v27), .macOS(.v27)
    ],
    products: [
        .library(
            name: "ExyteChat",
            targets: ["ExyteChat"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ExyteChat",
            dependencies: []
        ),
        .testTarget(
            name: "ExyteChatTests",
            dependencies: ["ExyteChat"]),
    ],
    swiftLanguageModes: [.v6]
)
