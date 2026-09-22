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
//  Portions of this project are based on the SRT protocol specification.
//  SRT is licensed under the Mozilla Public License, v. 2.0.
//  You may obtain a copy of the License at
//  https://github.com/Haivision/srt/blob/master/LICENSE
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
