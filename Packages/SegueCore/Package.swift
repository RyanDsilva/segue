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
    platforms: [.macOS("26.0")],
    products: [
        .library(
            name: "SegueCore",
            targets: [
                "ChordPro", "MusicTheory", "Diagrams", "Editing", "Library", "Setlists",
                "Shows", "LiveLayout", "Plugins", "Support", "Services", "Ingest", "ModelPort",
                "SetAssistant", "Playback", "Printing",
            ],
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
        // Phase 1 unit A: chord symbols, transposition, capo, Nashville, key detection.
        .target(
            name: "MusicTheory",
            dependencies: [
                .product(name: "Tonic", package: "Tonic"),
            ],
            swiftSettings: strictSettings,
        ),
        // Phase 1 unit B: tunings, guitar shapes, piano voicings, {define}, shape lookup.
        .target(
            name: "Diagrams",
            dependencies: ["MusicTheory", "Support"],
            swiftSettings: strictSettings,
        ),
        // Phase 1 unit C: source snapshot, tree edit operations -> text edits, render model.
        .target(
            name: "Editing",
            dependencies: [
                "ChordPro",
                "Diagrams",
                "MusicTheory",
                .product(name: "Tonic", package: "Tonic"),
            ],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Library",
            dependencies: [
                "ChordPro",
                "Diagrams",
                "Editing",
                "MusicTheory",
                "Support",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Setlists",
            dependencies: ["Editing", "Library", "MusicTheory", "Support"],
            swiftSettings: strictSettings,
        ),
        // Phase 2 unit A: show engine, show store, gig log, reorder diff, command layer.
        .target(
            name: "Shows",
            dependencies: ["Library", "Setlists", "Support"],
            swiftSettings: strictSettings,
        ),
        // Phase 2 unit B: live auto-fit layout and auto-scroll model (pure).
        .target(
            name: "LiveLayout",
            dependencies: ["ChordPro", "Editing", "Library", "Setlists"],
            swiftSettings: strictSettings,
        ),
        .target(
            name: "Plugins",
            dependencies: ["ChordPro", "Support"],
            swiftSettings: strictSettings,
        ),
        // WS3: hosted-services core (ports, closed analytics vocabulary, consent, safe log).
        // No vendor code: Foundation, Synchronization, os and CryptoKit only.
        .target(
            name: "Services",
            dependencies: ["Support"],
            swiftSettings: strictSettings,
        ),
        // Phase 3 P3-1: deterministic paste pipeline (normalize, detect, segment, convert,
        // validate, metadata, lyric guard, key inference). Pure; no model.
        .target(
            name: "Ingest",
            // Plugins: the source fields of `ingest(_:origin:source:)` (P9-4 spec 5.1).
            dependencies: ["ChordPro", "MusicTheory", "Plugins"],
            swiftSettings: strictSettings,
        ),
        // Phase 3 P3-2: the AI provider port (tasks, router, ScriptedProvider, paste
        // refinement). Pure; the Foundation Models and MLX adapters live in Packages/SegueAI.
        .target(
            name: "ModelPort",
            dependencies: ["Ingest"],
            swiftSettings: strictSettings,
        ),
        // Phase 3 P3-7: the set assistant (request lexicon, scorer with breakdowns, packer,
        // builder). Pure; the async model pass goes through ModelPort's router.
        .target(
            name: "SetAssistant",
            dependencies: [
                "Diagrams", "Editing", "Library", "ModelPort", "MusicTheory", "Setlists",
            ],
            swiftSettings: strictSettings,
        ),
        // P8-6: sound as pure note events (voicings, phrases, the lookahead cursor) behind
        // the `SoundOutput` port; the AVFoundation adapter lives in SegueUI.
        .target(
            name: "Playback",
            dependencies: ["Diagrams", "Editing", "Library", "MusicTheory", "Shows", "Support"],
            swiftSettings: strictSettings,
        ),
        // P9-1: the print document (options, set list rows, page numbers, outline, links,
        // metadata, file names). Pure; SegueUI draws it.
        .target(
            name: "Printing",
            dependencies: ["Editing", "Library", "LiveLayout", "Setlists"],
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "SegueCoreTests",
            dependencies: [
                "ChordPro", "MusicTheory", "Diagrams", "Editing", "Library", "Setlists",
                "Shows", "LiveLayout", "Plugins", "Support", "Services", "Ingest", "ModelPort",
                "SetAssistant", "Playback", "Printing",
                .product(name: "Tonic", package: "Tonic"),
            ],
            path: "Tests",
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings,
        ),
    ],
)
