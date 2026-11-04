// swift-tools-version: 6.0
// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import PackageDescription

let package = Package(
    name: "skyHAB",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "skyHAB", targets: ["skyHAB"])],
    targets: [
        .executableTarget(name: "skyHAB", path: "Sources/skyHAB"),
        .testTarget(name: "skyHABTests", dependencies: ["skyHAB"], path: "Tests/skyHABTests")
    ]
)
