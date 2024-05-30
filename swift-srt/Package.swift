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
            name: "SwiftSrt",
            targets: ["SwiftSrt"]),
    ],
    targets: [
        .target(
            name: "SwiftSrt"),
        .testTarget(
            name: "SwiftSrtTests",
            dependencies: ["SwiftSrt"]),
    ]
)
