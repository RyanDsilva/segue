import CryptoKit
import Foundation

/// Constants of our own TelemetryDeck ingest client (spec 3.9, R34). Mirrors the SwiftSDK
/// 2.14.2 reference implementation (`SignalManager.getServiceUrl`, `CryptoHashing`), minus
/// every default parameter the SDK adds.
public enum TelemetryDeckIngest {
    /// Fixed salt hashed with the per-install ID into `clientUser`. TelemetryDeck salts and
    /// hashes the value again on the server.
    static let salt = "6lbfi9Qrb1z9mXYb5MLWFFETphWsPBm8HDCAmPUsKY87x41FilIDUHfIvrJbxHaM"

    /// The `UserDefaults` key holding the random per-install analytics ID. Created on grant,
    /// deleted on revoke, so a re-grant starts a fresh, unlinkable identity.
    public static let installIDKey = "analytics.installID"

    /// The session signal TelemetryDeck's built-in user, session and retention insights use.
    static let sessionStartedType = "TelemetryDeck.Session.started"

    /// The ingest API v2 endpoint: `/v2/namespace/<namespace>/` when the organisation has a
    /// namespace, else the bare `/v2/` (API v1 is deprecated and never used).
    static func endpoint(namespace: String?) -> URL? {
        let suffix = namespace.map { "v2/namespace/\($0)/" } ?? "v2/"
        return URL(string: "https://nom.telemetrydeck.com/\(suffix)")
    }

    /// Lowercase hex SHA-256 of `installID + salt` (SDK `CryptoHashing.sha256(string:salt:)`).
    static func clientUser(installID: String) -> String {
        SHA256.hash(data: Data((installID + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// One signal object exactly as posted: these six keys and nothing else.
struct IngestSignal: Codable, Sendable, Hashable {
    let appID: String
    let clientUser: String
    let sessionID: String
    let type: String
    let isTestMode: Bool
    let payload: [String: String]

    /// Every key a posted signal object may carry.
    static let keys: Set = [
        "appID", "clientUser", "sessionID", "type", "isTestMode", "payload",
    ]
}

/// The five context keys our client adds to every signal (spec 3.9). Nothing else: no model,
/// architecture, time zone, screen, language, locale, colour scheme or accessibility data.
public struct IngestContext: Sendable, Hashable {
    public static let operatingSystemKey = "TelemetryDeck.Device.operatingSystem"
    public static let systemVersionKey = "TelemetryDeck.Device.systemMajorMinorVersion"
    public static let appVersionKey = "TelemetryDeck.AppInfo.version"
    public static let buildNumberKey = "TelemetryDeck.AppInfo.buildNumber"
    public static let regionKey = "TelemetryDeck.UserPreference.region"

    /// The allowlist of context keys.
    public static let keys: Set<String> = [
        operatingSystemKey, systemVersionKey, appVersionKey, buildNumberKey, regionKey,
    ]

    public var systemMajorMinorVersion: String
    public var appVersion: String
    public var buildNumber: String
    /// Two-letter country from the Mac's region setting; nil omits the key.
    public var region: String?

    public init(
        systemMajorMinorVersion: String,
        appVersion: String,
        buildNumber: String,
        region: String?,
    ) {
        self.systemMajorMinorVersion = systemMajorMinorVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.region = region
    }

    /// This Mac's context for an app version and build.
    public static func current(appVersion: String, buildNumber: String) -> Self {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            systemMajorMinorVersion: "\(os.majorVersion).\(os.minorVersion)",
            appVersion: appVersion,
            buildNumber: buildNumber,
            region: Locale.current.region?.identifier,
        )
    }

    /// The context as payload entries. A value outside the section 5 value allowlist is
    /// left out rather than sent.
    var payload: [String: String] {
        var entries = [
            Self.operatingSystemKey: "macOS",
            Self.systemVersionKey: systemMajorMinorVersion,
            Self.appVersionKey: appVersion,
            Self.buildNumberKey: buildNumber,
        ]
        entries[Self.regionKey] = region
        return entries.filter { IngestBody.isAllowedValue($0.value) }
    }
}

/// Who and where a signal comes from: fixed for the life of one sink.
struct IngestIdentity: Sendable, Hashable {
    let appID: String
    let clientUser: String
    let sessionID: String
    let isTestMode: Bool
}

/// Builds the request bodies. The only producer of `IngestSignal` values, so the allowlist
/// test (spec 14.2-9) covers every byte our client can send.
enum IngestBody {
    /// The value allowlist of spec section 5.
    static func isAllowedValue(_ value: String) -> Bool {
        value.wholeMatch(of: /[A-Za-z0-9+<>._-]{1,24}/) != nil
    }

    /// The signal for one rendered `AnalyticsEvent`: its `segue.*` params plus the context.
    static func make(
        type: String,
        params: [String: String],
        context: IngestContext,
        identity: IngestIdentity,
    ) -> IngestSignal {
        // Defence in depth: only `segue.*` params with allowlisted values get through, and a
        // param can never overwrite a context key.
        var payload = params.filter { key, value in
            key.hasPrefix("segue.") && isAllowedValue(value)
        }
        payload.merge(context.payload) { _, context in context }
        return IngestSignal(
            appID: identity.appID,
            clientUser: identity.clientUser,
            sessionID: identity.sessionID,
            type: type,
            isTestMode: identity.isTestMode,
            payload: payload,
        )
    }

    /// The session signal: context keys only.
    static func sessionStarted(context: IngestContext, identity: IngestIdentity) -> IngestSignal {
        make(
            type: TelemetryDeckIngest.sessionStartedType,
            params: [:],
            context: context,
            identity: identity,
        )
    }

    /// The JSON array posted in one request.
    static func encode(_ signals: [IngestSignal]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(signals)
    }
}
