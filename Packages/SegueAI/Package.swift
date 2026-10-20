// swift-tools-version: 6.2
//
// SegueAI: the AI provider adapters behind SegueCore's ModelPort (docs/phases/
// 3-ai-entry-and-assistant.md section 4, R77). Linked by BOTH app flavours. P3-2 adds the
// Foundation Models side (`GenerableTasks`, `FoundationModelsAdapter`, the manual recording
// runner); P3-3 adds MLX, the model store and `make eval-ai`.
//
// Tests are pure mapping tests: no real model call ever runs in `swift test`.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "SegueAI",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SegueAI", targets: ["GenerableTasks", "FoundationModelsAdapter"]),
        // Manual only (never run by tests or gates): records real FM outputs for
        // ScriptedProvider. P3-3 folds it into `make eval-ai RECORD=1`.
        .executable(name: "segue-ai-record", targets: ["segue-ai-record"]),
    ],
    dependencies: [
        .package(path: "../SegueCore"),
    ],
    targets: [
        // One @Generable wire type per task (no optionals, .anyOf enums, exact or maximum
        // counts), its mapping to the Core output, and the schema export MLX reuses.
        .target(
            name: "GenerableTasks",
            dependencies: [.product(name: "SegueCore", package: "SegueCore")],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "FoundationModelsAdapter",
            dependencies: [
                "GenerableTasks",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        .executableTarget(
            name: "segue-ai-record",
            dependencies: [
                "FoundationModelsAdapter",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "FoundationModelsAdapterMappingTests",
            dependencies: [
                "GenerableTasks",
                "FoundationModelsAdapter",
                .product(name: "SegueCore", package: "SegueCore"),
            ],
            swiftSettings: strictSettings,
        ),
    ],
)
