import ProjectDescription

// Segue - Tuist project manifest. Source of truth for targets, schemes, configurations,
// entitlements and signing; the generated .xcodeproj/.xcworkspace are gitignored and never
// hand-edited.

// MARK: - Signing

/// Apple Developer team used for automatic signing (a team ID is not a secret).
/// The paid individual Apple Developer Program team (Ryan Rony Dsilva), renewed 2026-10
/// (docs/release/decisions.md R1).
let developmentTeam = "V6BM673U35"

/// How builds are signed.
/// - `.automatic`: Xcode automatic signing with `developmentTeam`. Command-line builds need
///   `-allowProvisioningUpdates` (the Makefile passes it).
/// - `.adHoc`: "Sign to Run Locally" (identity "-"), no team or Apple account needed.
///   Fallback for machines where automatic signing is unavailable.
enum SigningMode {
    case automatic
    case adHoc
}

let signingMode: SigningMode = .automatic

let signingSettings: SettingsDictionary = switch signingMode {
case .automatic:
    [
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": .string(developmentTeam),
        "CODE_SIGN_IDENTITY": "Apple Development",
    ]
case .adHoc:
    [
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "",
        "CODE_SIGN_IDENTITY": "-",
    ]
}

// MARK: - Identity

/// The flavors have separate bundle IDs (docs/release/decisions.md R11), so each has its own
/// sandbox container and App ID. Quick Look extensions derive theirs as `<host>.quicklook`.
let appStoreBundleID = "dev.ryandsilva.segue"
let personalBundleID = "dev.ryandsilva.segue.personal"
let uiTestsBundleID = "dev.ryandsilva.segue.uitests"
let deploymentTargets: DeploymentTargets = .macOS("26.0")

// MARK: - Hosted services (WS3, docs/release/README.md "Service values")

/// Not secrets: a DSN and TelemetryDeck app IDs ship inside the app binary. The app reads
/// them from Info.plist (`VendorConfig` in Packages/SegueVendorServices).
let sentryDSN = "https://997bf383bbb7edd32a15c839fba202b8@o4512275137691648.ingest.us.sentry.io/4512275142475776"
let telemetryDeckAppIDAppStore = "CDF7AF01-FB23-4A30-AFAB-8EAB4BF6EFB5"
let telemetryDeckAppIDPersonal = "6E38DC85-EE5E-4ECF-A8E0-E4FDFDE9B208"
let telemetryDeckNamespace = "dev.ryandsilva"

// MARK: - Configurations

let debugPersonal: ConfigurationName = "Debug-Personal"
let releasePersonal: ConfigurationName = "Release-Personal"
let debugAppStore: ConfigurationName = "Debug-AppStore"
let releaseAppStore: ConfigurationName = "Release-AppStore"

let versionXCConfig: Path = "Config/Version.xcconfig"

/// Strict build settings applied to every target in this project.
let strictSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
    "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES",
    // Apple silicon only (docs/release/decisions.md R41, A59).
    "ARCHS": "arm64",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
]

let projectSettings: Settings = .settings(
    base: strictSettings.merging(signingSettings) { _, new in new },
    // Config/Version.xcconfig is the only place the version lives (MARKETING_VERSION,
    // CURRENT_PROJECT_VERSION); scripts/bump-version.sh edits it.
    configurations: [
        .debug(name: debugPersonal, xcconfig: versionXCConfig),
        .release(name: releasePersonal, xcconfig: versionXCConfig),
        .debug(name: debugAppStore, xcconfig: versionXCConfig),
        .release(name: releaseAppStore, xcconfig: versionXCConfig),
    ],
    defaultSettings: .recommended,
)

// MARK: - Targets

/// The Info.plist both flavors share (explicit, not Tuist's default, so no
/// NSMainStoryboardFile or empty CFBundleIconFile ships; the asset compiler adds the icon keys
/// from ASSETCATALOG_COMPILER_APPICON_NAME).
let appInfoPlist: [String: Plist.Value] = [
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    // R3: the Dock name stays "Segue".
    "CFBundleDisplayName": "Segue",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    // R3 primary category.
    "LSApplicationCategoryType": "public.app-category.music",
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "NSPrincipalClass": "NSApplication",
    // R30: one copyright string everywhere.
    "NSHumanReadableCopyright": "© 2026 Ryan Rony Dsilva",
    // Only CryptoKit hashing and OS-provided HTTPS, both exempt.
    "ITSAppUsesNonExemptEncryption": false,
    // R59 (Path SE): shown in the one-time Automation prompt for Shortcuts Events.
    "NSAppleEventsUsageDescription": """
    Segue runs your Gig Mode Shortcuts when a show starts and ends, for example to turn on \
    your Performing Focus, and checks that they finished. It runs only the Shortcuts you \
    name in Settings > Live.
    """,
    // Hosted services (WS3): filled from the per-flavor build settings in `appTarget`.
    "SegueSentryDSN": "$(SEGUE_SENTRY_DSN)",
    "SegueTelemetryDeckAppID": "$(SEGUE_TELEMETRYDECK_APP_ID)",
    "SegueTelemetryDeckNamespace": "$(SEGUE_TELEMETRYDECK_NAMESPACE)",
]

/// Both app flavors compile the same sources and share the Info.plist. They differ in bundle
/// ID (`personalBundleID` / `appStoreBundleID`, R11) and entitlements file: the App Store
/// flavor uses `App/SegueAppStore.entitlements` (asserted exactly by the release checks),
/// Personal uses `App/Segue.entitlements` (`App/Segue-Debug.entitlements` in Debug-Personal).
/// They are separate targets because SwiftPM product dependencies are per-target, not
/// per-configuration: only `Segue` (Personal) links `SeguePersonalModules`, so the App Store
/// flavor never references that package.
func appTarget(name: String, personal: Bool) -> Target {
    let entitlementsPath = personal ? "App/Segue.entitlements" : "App/SegueAppStore.entitlements"
    var dependencies: [TargetDependency] = [
        .external(name: "SegueUI"),
        .external(name: "SegueCore"),
        // Hosted services (WS3): our TelemetryDeck ingest client and the Sentry SDK.
        .external(name: "VendorServices"),
    ]
    var settings: SettingsDictionary = [
        "PRODUCT_NAME": "Segue",
        "CODE_SIGN_ENTITLEMENTS": .string(entitlementsPath),
        "ENABLE_APP_SANDBOX": "YES",
        // Agrees with `com.apple.security.network.client` in every entitlements file (A61), so
        // the sandbox build setting and the entitlements never disagree.
        "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES",
        // Matches the `.icon` document name (design/icon/Segue.icon).
        "ASSETCATALOG_COMPILER_APPICON_NAME": "Segue",
        // Every icon size from the .icon document, so the App Store build's icon checks
        // pass (WS1 check 10).
        "ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR": "all",
        // No app accent colour: controls keep the system accent, because coral is reserved
        // for the cue and is never a control fill (docs/brand.md section 7).
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
        // Read through Info.plist by VendorConfig; each flavor has its own TelemetryDeck app.
        "SEGUE_SENTRY_DSN": .string(sentryDSN),
        "SEGUE_TELEMETRYDECK_APP_ID": .string(
            personal ? telemetryDeckAppIDPersonal : telemetryDeckAppIDAppStore,
        ),
        "SEGUE_TELEMETRYDECK_NAMESPACE": .string(telemetryDeckNamespace),
        // sentry-cocoa's static targets declare `linkedLibrary("c++")` and `("z")` in their
        // package manifest; Tuist's static frameworks do not pass that on to the app's link.
        "OTHER_LDFLAGS": "$(inherited) -lc++ -lz",
    ]
    if personal {
        dependencies.append(.external(name: "SeguePersonalModules"))
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) SEGUE_PERSONAL"
    }
    return .target(
        name: name,
        destinations: [.mac],
        product: .app,
        productName: "Segue",
        bundleId: personal ? personalBundleID : appStoreBundleID,
        deploymentTargets: deploymentTargets,
        infoPlist: .dictionary(appInfoPlist),
        sources: ["App/Sources/**"],
        // App icon: the Icon Composer document generated by scripts/gen-icon.swift. Colour
        // tokens and fonts ship in the SegueUI package's resource bundle, not here. The
        // privacy manifest lands at Contents/Resources/PrivacyInfo.xcprivacy. What's New reads
        // WS4's generated changelog from the bundle (WS2b 4.3, B-26); it is never fetched.
        resources: [
            "design/icon/Segue.icon", "App/PrivacyInfo.xcprivacy", "website/changelog.json",
        ],
        entitlements: .file(path: .relativeToRoot(entitlementsPath)),
        scripts: [stampResourceBundle],
        dependencies: dependencies,
        // Signing is repeated at target level because Tuist's target defaults set
        // CODE_SIGN_IDENTITY for macOS, which would override the project-level value.
        settings: .settings(
            base: settings.merging(signingSettings) { _, new in new },
            configurations: personal ? [e2eDebugConfiguration] : [],
        ),
    )
}

/// `Debug-Personal` only: entitlements that add a sandbox temporary exception for the E2E
/// library path (`/private/tmp/segue-e2e/`), so XCUITests can point the app at a fresh temp
/// library via `-SegueLibraryPath` without the open panel. Release-Personal keeps
/// `App/Segue.entitlements` and the App Store target `App/SegueAppStore.entitlements`; neither
/// ever carries it
/// (`make verify-appstore` checks the shipped products).
let e2eDebugConfiguration: Configuration = .debug(
    name: debugPersonal,
    settings: ["CODE_SIGN_ENTITLEMENTS": "App/Segue-Debug.entitlements"],
)

/// After resources are copied and before signing: the SegueUI resource bundle gets the app's
/// copyright and version and a real identifier instead of Tuist's placeholder plist (B-6).
let resourcesFolder = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)"
let segueUIBundle = "\(resourcesFolder)/SegueUI_SegueUI.bundle"
let stampResourceBundle: TargetScript = .post(
    path: "scripts/stamp-resource-bundle.sh",
    name: "Stamp SegueUI resource bundle",
    inputPaths: [
        "$(SRCROOT)/scripts/stamp-resource-bundle.sh",
        "$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)",
        "\(segueUIBundle)",
    ],
    // The plist is a declared output: with user-script sandboxing on, PlistBuddy may only
    // write to declared outputs, and it exits 0 when the sandbox denies the write.
    outputPaths: [
        "$(DERIVED_FILE_DIR)/stamp-resource-bundle.stamp",
        "\(segueUIBundle)/Contents/Info.plist",
    ],
    basedOnDependencyAnalysis: false,
)

let personalApp = appTarget(name: "Segue", personal: true)
let appStoreApp = appTarget(name: "SegueAppStore", personal: false)

let uiTests: Target = .target(
    name: "SegueUITests",
    destinations: [.mac],
    product: .uiTests,
    bundleId: uiTestsBundleID,
    deploymentTargets: deploymentTargets,
    infoPlist: .default,
    sources: ["UITests/**"],
    // Merged into the sandboxed test runner: read-write access to the E2E temp library
    // (/private/tmp/segue-e2e/). Test-only; never part of an app product.
    entitlements: .file(path: "UITests/SegueUITests.entitlements"),
    dependencies: [.target(name: "Segue")],
    settings: .settings(base: signingSettings.merging(["TEST_TARGET_NAME": "Segue"]) { _, new in
        new
    }),
)

// MARK: - Schemes

let personalScheme: Scheme = .scheme(
    name: "Segue-Personal",
    shared: true,
    buildAction: .buildAction(targets: ["Segue"]),
    testAction: .targets(
        [.testableTarget(target: "SegueUITests")],
        configuration: debugPersonal,
    ),
    runAction: .runAction(configuration: debugPersonal, executable: "Segue"),
    archiveAction: .archiveAction(configuration: releasePersonal),
    profileAction: .profileAction(configuration: releasePersonal, executable: "Segue"),
    analyzeAction: .analyzeAction(configuration: debugPersonal),
)

let appStoreScheme: Scheme = .scheme(
    name: "Segue-AppStore",
    shared: true,
    buildAction: .buildAction(targets: ["SegueAppStore"]),
    runAction: .runAction(configuration: debugAppStore, executable: "SegueAppStore"),
    archiveAction: .archiveAction(configuration: releaseAppStore),
    profileAction: .profileAction(configuration: releaseAppStore, executable: "SegueAppStore"),
    analyzeAction: .analyzeAction(configuration: debugAppStore),
)

// MARK: - Project

let project = Project(
    name: "Segue",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "en",
    ),
    settings: projectSettings,
    targets: [personalApp, appStoreApp, uiTests],
    schemes: [personalScheme, appStoreScheme],
)
