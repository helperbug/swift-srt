// swift-tools-version: 6.4
//
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import PackageDescription

let package = Package(
    name: "swift-srt",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftSrt",
            targets: ["SwiftSrt"]),
        .library(
            name: "SwiftSrtMedia",
            targets: ["SwiftSrtMedia"]),
        .executable(
            name: "srt-receive",
            targets: ["srt-receive"]),
        .executable(
            name: "srt-send",
            targets: ["srt-send"]),
        .executable(
            name: "srt-player",
            targets: ["srt-player"]),
        .executable(
            name: "srt-testpattern",
            targets: ["srt-testpattern"]),
        .library(
            name: "SrtNetem",
            targets: ["SrtNetem"]),
        .executable(
            name: "srt-netem",
            targets: ["srt-netem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "SwiftSrt",
            path: "Sources/swift-srt"),
        .target(
            name: "SwiftSrtMedia",
            dependencies: ["SwiftSrt"],
            path: "Sources/SwiftSrtMedia"),
        .executableTarget(
            name: "srt-player",
            dependencies: ["SwiftSrt", "SwiftSrtMedia"],
            path: "Sources/srt-player"),
        .target(
            name: "SrtNetem",
            path: "Sources/SrtNetem"),
        .executableTarget(
            name: "srt-netem",
            dependencies: ["SrtNetem"],
            path: "Sources/srt-netem"),
        .executableTarget(
            name: "srt-testpattern",
            path: "Sources/srt-testpattern"),
        .executableTarget(
            name: "srt-send",
            dependencies: ["SwiftSrt"],
            path: "Sources/srt-send"),
        .executableTarget(
            name: "srt-receive",
            dependencies: ["SwiftSrt"],
            path: "Sources/srt-receive"),
        .testTarget(
            name: "SwiftSrtTests",
            dependencies: ["SwiftSrt", "SwiftSrtMedia", "SrtNetem"],
            path: "Tests/SwiftSrtTests"),
    ],
    swiftLanguageModes: [.v6]
)
