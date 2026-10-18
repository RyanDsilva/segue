// swift-tools-version: 6.2
//
// External dependencies for the Tuist-generated workspace. Local packages under
// `Packages/` are integrated as Xcode targets through here, alongside GRDB and Tonic.
// GRDB and Tonic are pinned to the SAME exact versions as `Packages/SegueCore/Package.swift`.

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

    let packageSettings = PackageSettings(
        productTypes: [:],
        baseSettings: .settings(
            // arm64 only, like the app targets (docs/release/decisions.md R41, A59).
            base: ["MACOSX_DEPLOYMENT_TARGET": "26.0", "ARCHS": "arm64"],
            configurations: configurationNames.map { name in
                name.hasPrefix("Debug")
                    ? .debug(name: ConfigurationName(stringLiteral: name))
                    : .release(name: ConfigurationName(stringLiteral: name))
            },
        ),
        targetSettings: Dictionary(
            uniqueKeysWithValues: [
                "ChordPro", "MusicTheory", "Diagrams", "Editing", "Library", "Setlists", "Shows",
                "LiveLayout", "Plugins", "Support",
                "SegueUI", "SeguePersonalModules",
            ].map { ($0, firstPartyStrict) },
        ),
    )
#endif

let package = Package(
    name: "SegueDependencies",
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/AudioKit/Tonic", exact: "2.1.2"),
        .package(path: "../Packages/SegueCore"),
        .package(path: "../Packages/SegueUI"),
        .package(path: "../Packages/SeguePersonalModules"),
    ],
)
