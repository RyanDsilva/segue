// swift-tools-version: 6.2
//
// SeguePersonalModules: restricted, personal-build-only plugins (phase 5) and Settings > AI >
// Advanced custom models (R62, R97). Linked ONLY by the `Segue` (Personal) app target. The App
// Store target and SegueCore must never reference this package; `make verify-appstore` checks
// the built product.
//
// P9-4 (lyrics search and URL import, spec 4.4): SwiftSoup is pinned exactly (R182) and
// imported only in `Sources/SeguePersonalModules/Web/` (the `swiftsoup_import` lint rule).
// `Tuist/Package.swift` pins it to the same exact version.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SeguePersonalModules",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SeguePersonalModules", targets: ["SeguePersonalModules"]),
        // P9-4 spec 16.3: the offline parse-accuracy eval (`make eval-import`), never linked
        // by the app and never part of quick, gate or check.
        .executable(name: "segue-import-eval", targets: ["segue-import-eval"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
        .package(path: "../SegueUI"),
        .package(path: "../SegueAI"),
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.14.3"),
    ],
    targets: [
        .target(
            name: "SeguePersonalModules",
            dependencies: [
                .product(name: "SegueCore", package: "SegueCore"),
                .product(name: "SegueUI", package: "SegueUI"),
                .product(name: "SegueAI", package: "SegueAI"),
                .product(name: "SegueAIEval", package: "SegueAI"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            swiftSettings: strictSettings,
        ),
        .executableTarget(
            name: "segue-import-eval",
            dependencies: [
                "SeguePersonalModules",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        // Offline only (spec 15): every test reaches the network through an injected
        // transport fed from the committed, lyric-redacted fixtures.
        .testTarget(
            name: "SeguePersonalModulesTests",
            dependencies: [
                "SeguePersonalModules",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings,
        ),
    ],
)
