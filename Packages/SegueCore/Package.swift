// swift-tools-version: 6.2
//
// SegueCore: platform-neutral core (no SwiftUI/AppKit). Each source folder is its own
// module so dependencies between them stay explicit.
//
// GRDB and Tonic are pinned to the SAME exact versions as `Tuist/Package.swift`.
// Exact-vs-exact pins make SwiftPM resolution fail loudly if the two ever drift.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SegueCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(
            name: "SegueCore",
            targets: ["ChordPro", "Library", "Setlists", "Plugins", "Support"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/AudioKit/Tonic", exact: "2.1.2"),
    ],
    targets: [
        .target(
            name: "Support",
            swiftSettings: strictSettings,
        ),
        .target(
            name: "ChordPro",
            dependencies: [
                .product(name: "Tonic", package: "Tonic"),
            ],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Library",
            dependencies: [
                "ChordPro",
                "Support",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Setlists",
            dependencies: ["Library", "Support"],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Plugins",
            dependencies: ["ChordPro", "Support"],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "SegueCoreTests",
            dependencies: ["ChordPro", "Library", "Setlists", "Plugins", "Support"],
            path: "Tests",
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings,
        ),
    ],
)
