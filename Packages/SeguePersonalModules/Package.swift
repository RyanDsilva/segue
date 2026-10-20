// swift-tools-version: 6.2
//
// SeguePersonalModules: restricted, personal-build-only plugins (phase 5) and Settings > AI >
// Advanced custom models (R62, R97). Linked ONLY by the `Segue` (Personal) app target. The App
// Store target and SegueCore must never reference this package; `make verify-appstore` checks
// the built product.

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
    ],
    dependencies: [
        .package(path: "../SegueCore"),
        .package(path: "../SegueUI"),
        .package(path: "../SegueAI"),
    ],
    targets: [
        .target(
            name: "SeguePersonalModules",
            dependencies: [
                .product(name: "SegueCore", package: "SegueCore"),
                .product(name: "SegueUI", package: "SegueUI"),
                .product(name: "SegueAI", package: "SegueAI"),
                .product(name: "SegueAIEval", package: "SegueAI"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
