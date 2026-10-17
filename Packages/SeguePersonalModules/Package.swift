// swift-tools-version: 6.2
//
// SeguePersonalModules: restricted, personal-build-only plugins (phase 5).
// Linked ONLY by the `Segue` (Personal) app target. The App Store target and SegueCore
// must never reference this package; `make verify-appstore` checks the built product.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SeguePersonalModules",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "SeguePersonalModules", targets: ["SeguePersonalModules"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
    ],
    targets: [
        .target(
            name: "SeguePersonalModules",
            dependencies: [
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
