// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-srt",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "swift-srt",
            targets: ["swift-srt"]),
    ],
    targets: [
        .target(
            name: "swift-srt",
            resources: [
                .process("Documentation/Resources/doclogo.png")
            ]),
        .testTarget(
            name: "swift-srtTests",
            dependencies: ["swift-srt"]),
    ]
)
