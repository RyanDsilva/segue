// swift-tools-version: 6.2
//
// SegueUI: SwiftUI views shared by the macOS app (and iOS later). Depends on SegueCore.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SegueUI",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "SegueUI", targets: ["SegueUI"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
    ],
    targets: [
        .target(
            name: "SegueUI",
            dependencies: [
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
