import CryptoKit
import Foundation

/// One file a bug report may attach (a log, the MetricKit JSON, the song file or its
/// sidecar). `name` is a bare file name, never a path.
public struct DiagnosticFile: Sendable, Hashable {
    public var name: String
    /// MIME type sent as the attachment's `content_type` (e.g. `text/plain`).
    public var contentType: String
    public var data: Data

    public init(name: String, contentType: String, data: Data) {
        self.name = name
        self.contentType = contentType
        self.data = data
    }
}

/// A file attached to a report, tagged with why it is there (the analytics row
/// `Segue.Feedback.sent` reports which kinds were attached, never their content).
public struct FeedbackAttachment: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case log
        case metricKit
        case songFile
        case songSidecar
    }

    public var kind: Kind
    public var file: DiagnosticFile

    public init(kind: Kind, file: DiagnosticFile) {
        self.kind = kind
        self.file = file
    }
}

/// The always-included system information of a report (spec 8.2 item 5). Every field is
/// shown in the preview as a label/value row and sent under `contexts.segue` with the same
/// key; nothing else describes the Mac. No serial numbers, host name, user name or paths.
public struct FeedbackSystemInfo: Sendable, Hashable {
    public var appVersion: String
    public var buildNumber: String
    public var flavor: String
    public var macOSVersion: String
    /// `hw.model`, e.g. `Mac15,3`.
    public var modelIdentifier: String
    public var architecture: String
    public var preferredLanguage: String
    public var songs: SongBucket
    public var setlists: SmallBucket
    public var gigs: SmallBucket
    public var analyticsConsent: String
    public var crashReportsConsent: String
    /// Total size of the diagnostic log files on disk, in bytes.
    public var logBytes: Int

    public init(
        appVersion: String,
        buildNumber: String,
        flavor: String,
        macOSVersion: String,
        modelIdentifier: String,
        architecture: String,
        preferredLanguage: String,
        songs: SongBucket,
        setlists: SmallBucket,
        gigs: SmallBucket,
        analyticsConsent: String,
        crashReportsConsent: String,
        logBytes: Int,
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.flavor = flavor
        self.macOSVersion = macOSVersion
        self.modelIdentifier = modelIdentifier
        self.architecture = architecture
        self.preferredLanguage = preferredLanguage
        self.songs = songs
        self.setlists = setlists
        self.gigs = gigs
        self.analyticsConsent = analyticsConsent
        self.crashReportsConsent = crashReportsConsent
        self.logBytes = logBytes
    }

    /// One row of the preview and one key of `contexts.segue`.
    public struct Field: Sendable, Hashable {
        /// The JSON key under `contexts.segue`.
        public let key: String
        /// The label the preview shows.
        public let label: String
        public let value: String
    }

    /// Every field, in preview order. The envelope and the preview both read this list, so
    /// they cannot disagree.
    public var fields: [Field] {
        [
            Field(key: "app_version", label: "App version", value: appVersion),
            Field(key: "build", label: "Build", value: buildNumber),
            Field(key: "flavor", label: "Flavor", value: flavor),
            Field(key: "macos_version", label: "macOS version", value: macOSVersion),
            Field(key: "model", label: "Mac model", value: modelIdentifier),
            Field(key: "arch", label: "CPU architecture", value: architecture),
            Field(key: "language", label: "Preferred language", value: preferredLanguage),
            Field(key: "songs", label: "Songs", value: songs.rawValue),
            Field(key: "setlists", label: "Setlists", value: setlists.rawValue),
            Field(key: "gigs", label: "Gigs", value: gigs.rawValue),
            Field(key: "consent_analytics", label: "Usage analytics", value: analyticsConsent),
            Field(
                key: "consent_crash_reports",
                label: "Crash reports",
                value: crashReportsConsent,
            ),
            Field(key: "log_bytes", label: "Log files size (bytes)", value: String(logBytes)),
        ]
    }
}

/// What the user filled in and chose to attach. The preview renders it and
/// `FeedbackReportBuilder` serialises it; both read the same value.
public struct FeedbackReport: Sendable, Hashable {
    /// "What happened?", as typed (trimmed of leading and trailing whitespace when built).
    public var message: String
    /// Optional reply-to address; nil or empty means none.
    public var email: String?
    public var systemInfo: FeedbackSystemInfo
    public var attachments: [FeedbackAttachment]

    public init(
        message: String,
        email: String?,
        systemInfo: FeedbackSystemInfo,
        attachments: [FeedbackAttachment],
    ) {
        self.message = message
        self.email = email
        self.systemInfo = systemInfo
        self.attachments = attachments
    }
}

/// A report frozen when its preview opens: the exact envelope bytes that Send posts.
/// Changing anything in the form builds a new payload (and needs a new preview).
public struct FeedbackPayload: Sendable, Hashable {
    /// The report the bytes were built from (the preview renders this).
    public let report: FeedbackReport
    /// Sentry event id: 32 lowercase hex characters.
    public let eventID: String
    /// The complete Sentry envelope.
    public let envelope: Data

    /// Lowercase hex SHA-256 of `envelope` (E2E compares what was previewed with what was
    /// sent through this value).
    public var sha256: String {
        SHA256.hash(data: envelope).map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a report could not be built. Shown in the form; nothing is truncated silently.
public enum FeedbackReportError: Error, Equatable, Sendable {
    /// The description is empty after trimming whitespace.
    case emptyMessage
    /// The description has more Unicode code points than Sentry accepts.
    case messageTooLong(limit: Int)
    /// The feedback context (description and email) is over Sentry's byte budget.
    case feedbackContextTooLarge(limit: Int)
    /// The whole envelope is over the report size cap.
    case tooLarge(limit: Int)
    /// An attachment name is empty or contains a path separator.
    case invalidAttachmentName
}

/// Why sending a frozen payload failed (`FeedbackSender.send`). Every case offers the
/// email / save-to-file fallback.
public enum FeedbackError: Error, Equatable, Sendable {
    case offline
    case rejected(status: Int)
    case tooLarge
    case notConfigured
}
