// swift-tools-version: 6.2
//
// SegueVendorServices: the ONLY code that knows a hosted vendor (WS3 spec 3.1). It implements
// the SegueCore `Services` ports with our own TelemetryDeck ingest client (no TelemetryDeck
// SDK, R34) and the Sentry SDK. Only the app targets link it; a SwiftLint rule fails any
// vendor import elsewhere.
//
// sentry-cocoa is pinned to the SAME exact version as `Tuist/Package.swift`.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SegueVendorServices",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VendorServices", targets: ["VendorServices"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.30.2"),
    ],
    targets: [
        .target(
            name: "VendorServices",
            dependencies: [
                .product(name: "SegueCore", package: "SegueCore"),
                .product(name: "SentrySPM", package: "sentry-cocoa"),
            ],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "VendorServicesTests",
            dependencies: [
                "VendorServices",
                .product(name: "SegueCore", package: "SegueCore"),
                .product(name: "SentrySPM", package: "sentry-cocoa"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
