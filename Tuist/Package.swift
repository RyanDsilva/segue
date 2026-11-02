// swift-tools-version: 6.2
//
// External dependencies for the Tuist-generated workspace. Local packages under
// `Packages/` are integrated as Xcode targets through here, alongside GRDB and Tonic.
// GRDB and Tonic are pinned to the SAME exact versions as `Packages/SegueCore/Package.swift`,
// sentry-cocoa to the same exact version as `Packages/SegueVendorServices/Package.swift`,
// mlx-swift-lm and swift-transformers to the same exact versions as `Packages/SegueAI`,
// SwiftSoup to the same exact version as `Packages/SeguePersonalModules/Package.swift`.

import PackageDescription

#if TUIST
    import ProjectDescription

    /// Build configurations must match `Project.swift`.
    private let configurationNames = [
        "Debug-Personal", "Release-Personal", "Debug-AppStore", "Release-AppStore",
    ]

    /// Our own package targets keep strict settings (Tuist suppresses warnings for external
    /// targets by default; first-party code must stay warning-free).
    private let firstPartyStrict: SettingsDictionary = [
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
        "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
        "SWIFT_SUPPRESS_WARNINGS": "NO",
        "GCC_WARN_INHIBIT_ALL_WARNINGS": "NO",
    ]

    /// sentry-cocoa's static targets hold files that compile to nothing on macOS (iOS-only
    /// and other-architecture sources); libtool warns once per such object, and the build's
    /// zero-warning gate (scripts/xcodebuild.sh) would fail on a vendored dependency's layout.
    private let sentryStaticTargets = [
        "_SentryCrashV9Headers", "_SentryPrivate", "SentryCrashV9", "SentryCrashV9Swift",
        "SentryHeaders", "SentryObjCInternal", "SentrySwift",
    ]
    private let quietLibtool: SettingsDictionary = [
        "OTHER_LIBTOOLFLAGS": "$(inherited) -no_warning_for_no_symbols",
    ]

    /// Static libraries, not Tuist's default static frameworks: the Quick Look extension
    /// (WS2b 4.7) links SegueUI and everything under it, and Tuist allows a macOS app
    /// extension to link static libraries only. The app links them the same way.
    private let staticLibraries = [
        "ChordPro", "MusicTheory", "Diagrams", "Editing", "Library", "Setlists", "Shows",
        "LiveLayout", "Plugins", "Support", "Services", "SegueCore", "SegueUI", "Tonic",
        // Phase 3 (P3-2): the paste pipeline, the AI port and the FM adapter.
        "Ingest", "ModelPort", "GenerableTasks", "FoundationModelsAdapter",
        // Phase 3 (P3-3): the model store, the MLX provider and its MLX binding.
        "ModelStore", "MLXAdapter", "MLXEngine", "AIEval",
        // Phase 3 (P3-7): the set assistant. Phase 8 (P8-6): the playback core.
        "SetAssistant", "Playback",
        // Phase 9 (P9-1): the print document.
        "Printing",
    ]

    let packageSettings = PackageSettings(
        productTypes: Dictionary(
            uniqueKeysWithValues: staticLibraries.map { ($0, .staticLibrary) },
        ),
        baseSettings: .settings(
            base: [
                // arm64 only, like the app targets (docs/release/decisions.md R41, A59).
                "MACOSX_DEPLOYMENT_TARGET": "26.0", "ARCHS": "arm64",
                // MLX's Metal kernels (the only Metal sources in any package) use C++17/20
                // features; upstream builds them with these flags (mlx/backend/metal/kernels/
                // CMakeLists.txt). Tuist's warning suppression does not reach the Metal
                // compiler, and a per-target setting does not reach the synthesized
                // mlx-swift_Cmlx resource-bundle target that compiles them (P3-A 5.2).
                "MTL_COMPILER_FLAGS": "$(inherited) -Wno-c++17-extensions -Wno-c++20-extensions",
            ],
            configurations: configurationNames.map { name in
                name.hasPrefix("Debug")
                    ? .debug(name: ConfigurationName(stringLiteral: name))
                    : .release(name: ConfigurationName(stringLiteral: name))
            },
        ),
        targetSettings: Dictionary(
            uniqueKeysWithValues: [
                "ChordPro", "MusicTheory", "Diagrams", "Editing", "Library", "Setlists", "Shows",
                "LiveLayout", "Plugins", "Support", "Services", "Ingest", "ModelPort",
                "SegueUI", "SeguePersonalModules", "VendorServices",
                "GenerableTasks", "FoundationModelsAdapter", "segue-eval", "AIEval",
                "ModelStore", "MLXAdapter", "MLXEngine", "SetAssistant", "Playback", "Printing",
            ].map { ($0, firstPartyStrict) } + (sentryStaticTargets + ["_NumericsShims"]).map {
                // swift-numerics' shim target compiles to no symbols, like sentry's iOS files.
                ($0, quietLibtool)
            },
        ),
    )
#endif

let package = Package(
    name: "SegueDependencies",
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/AudioKit/Tonic", exact: "2.1.2"),
        // WS3: the Sentry SDK (no TelemetryDeck package: our own ingest client, R34).
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.30.2"),
        .package(path: "../Packages/SegueCore"),
        .package(path: "../Packages/SegueUI"),
        .package(path: "../Packages/SeguePersonalModules"),
        .package(path: "../Packages/SegueVendorServices"),
        // Phase 3 (P3-2): the AI adapters, in both flavours (R62, R77).
        .package(path: "../Packages/SegueAI"),
        // Phase 3 (P3-3): MLX + tokenizer, pinned like Packages/SegueAI/Package.swift.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
        // Phase 9 (P9-4): the HTML parser of the Personal build's web import, pinned like
        // Packages/SeguePersonalModules/Package.swift (R182). The App Store target never links it.
        .package(url: "https://github.com/scinfu/SwiftSoup", exact: "2.14.3"),
    ],
)
