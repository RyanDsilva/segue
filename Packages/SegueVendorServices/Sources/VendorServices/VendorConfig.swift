import Foundation

/// The vendor values a build ships with (spec 3.7). None is secret: a Sentry DSN and a
/// TelemetryDeck App ID are designed to live in client binaries. They come from per-target
/// build settings through the app's Info.plist keys below.
public struct VendorConfig: Sendable, Hashable {
    /// Info.plist keys (`$(SEGUE_SENTRY_DSN)`, `$(SEGUE_TELEMETRYDECK_APP_ID)`,
    /// `$(SEGUE_TELEMETRYDECK_NAMESPACE)`).
    public enum InfoKey {
        public static let sentryDSN = "SegueSentryDSN"
        public static let telemetryDeckAppID = "SegueTelemetryDeckAppID"
        public static let telemetryDeckNamespace = "SegueTelemetryDeckNamespace"
    }

    public let sentryDSN: SentryDSN
    /// The TelemetryDeck App ID (App Store or Personal app), uppercase UUID form.
    public let telemetryDeckAppID: String
    /// The organisation namespace, or nil for the bare `/v2/` endpoint.
    public let telemetryDeckNamespace: String?
    /// The TelemetryDeck ingest endpoint (spec 3.9).
    public let telemetryDeckEndpoint: URL
    public let bundleIdentifier: String
    /// `CFBundleShortVersionString`.
    public let appVersion: String
    /// `CFBundleVersion`.
    public let buildNumber: String

    /// Validates every value; nil when any is missing or malformed, so the app uses Null
    /// adapters and says the services are not part of this build.
    public init?(
        sentryDSN: String,
        telemetryDeckAppID: String,
        telemetryDeckNamespace: String,
        bundleIdentifier: String,
        appVersion: String,
        buildNumber: String,
    ) {
        guard let dsn = SentryDSN(sentryDSN),
              let appID = UUID(uuidString: telemetryDeckAppID),
              !bundleIdentifier.isEmpty, !appVersion.isEmpty, !buildNumber.isEmpty
        else {
            return nil
        }
        let namespace = telemetryDeckNamespace.trimmingCharacters(in: .whitespaces)
        if !namespace.isEmpty, namespace.wholeMatch(of: /[A-Za-z0-9._-]{1,64}/) == nil {
            return nil
        }
        guard let endpoint = TelemetryDeckIngest.endpoint(
            namespace: namespace.isEmpty ? nil : namespace,
        ) else {
            return nil
        }
        telemetryDeckEndpoint = endpoint
        self.sentryDSN = dsn
        self.telemetryDeckAppID = appID.uuidString
        self.telemetryDeckNamespace = namespace.isEmpty ? nil : namespace
        self.bundleIdentifier = bundleIdentifier
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    /// Reads the config from an Info.plist dictionary.
    public init?(info: [String: Any]) {
        func string(_ key: String) -> String {
            (info[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.init(
            sentryDSN: string(InfoKey.sentryDSN),
            telemetryDeckAppID: string(InfoKey.telemetryDeckAppID),
            telemetryDeckNamespace: string(InfoKey.telemetryDeckNamespace),
            bundleIdentifier: string("CFBundleIdentifier"),
            appVersion: string("CFBundleShortVersionString"),
            buildNumber: string("CFBundleVersion"),
        )
    }

    /// Reads the config from a bundle (the app passes `Bundle.main`).
    public static func load(from bundle: Bundle) -> Self? {
        Self(info: bundle.infoDictionary ?? [:])
    }

    /// The Sentry release, `<bundle id>@<version>+<build>` (matches the dSYM upload).
    public var sentryReleaseName: String {
        "\(bundleIdentifier)@\(appVersion)+\(buildNumber)"
    }
}

/// Where a build runs. Picked by the app's wiring (`AppTransaction` environment, flavour and
/// the Debug-only `-SegueServicesLive` flag).
public enum VendorEnvironment: String, Sendable, CaseIterable {
    /// Release-AppStore from the App Store.
    case production
    /// Release-AppStore whose `AppTransaction` environment is sandbox.
    case testflight
    /// Release-Personal (its own TelemetryDeck app, so its signals are real data there).
    case personal
    /// Debug builds with `-SegueServicesLive YES`.
    case debug

    /// The Sentry `environment` value.
    public var sentryEnvironment: String {
        rawValue
    }

    /// TelemetryDeck `isTestMode` (spec 3.9, B-25).
    public var isTestMode: Bool {
        switch self {
        case .debug, .testflight: true
        case .personal, .production: false
        }
    }
}

/// A parsed Sentry DSN, `https://<public key>@<host>/<project id>`.
public struct SentryDSN: Sendable, Hashable, CustomStringConvertible {
    public let publicKey: String
    public let host: String
    public let projectID: String
    /// The project's envelope endpoint (bug reports, spec 3.5).
    public let envelopeURL: URL

    public init?(_ string: String) {
        guard let match = string.wholeMatch(
            of: /https:\/\/([0-9a-f]+)@([a-z0-9.-]+)\/([0-9]+)/,
        ),
            let envelope = URL(string: "https://\(match.2)/api/\(match.3)/envelope/")
        else {
            return nil
        }
        publicKey = String(match.1)
        host = String(match.2)
        projectID = String(match.3)
        envelopeURL = envelope
    }

    public var description: String {
        "https://\(publicKey)@\(host)/\(projectID)"
    }
}
