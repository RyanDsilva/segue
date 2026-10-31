import Foundation

// Phase 3 AI analytics (R74, R98; spec section 11): rows 19-22 of the closed vocabulary.
// Enums, buckets and booleans only: never song text, titles, artists, tags, queries or model
// names.

// MARK: - Row 19: Segue.AI.pasteFinished

/// One pasted or converted song leaving the review sheet.
public struct PasteFinishedSummary: Sendable, Hashable {
    public var source: PasteSource
    public var provider: AIProviderUsed
    public var fallback: PasteFallback
    /// How long the AI refinement ran (`none` when no model was asked).
    public var latency: LatencyBucket
    public var outcome: PasteOutcome
    /// How much the user changed what the AI decided before Accept.
    public var correction: CorrectionBucket
    /// The converter's romanized-Hindi detection fired (R98).
    public var romanHindi: Bool

    public init(
        source: PasteSource,
        provider: AIProviderUsed,
        fallback: PasteFallback,
        latency: LatencyBucket,
        outcome: PasteOutcome,
        correction: CorrectionBucket,
        romanHindi: Bool,
    ) {
        self.source = source
        self.provider = provider
        self.fallback = fallback
        self.latency = latency
        self.outcome = outcome
        self.correction = correction
        self.romanHindi = romanHindi
    }
}

/// How the song reached the review sheet.
public enum PasteSource: String, Sendable, CaseIterable {
    /// File > New Song from Clipboard.
    case clipboard
    /// New Song's input state.
    case newSong
    /// The empty library's "Paste a Song".
    case emptyState
    /// Command-V on the song list.
    case listPaste
    case fileTxt
    case fileCrd
    /// An already-ChordPro file that looks like a library song, reviewed for its warning
    /// (P8-1, R158 Q4).
    case fileCho
}

/// Which provider answered (shared by rows 19 and 21).
public enum AIProviderUsed: String, Sendable, CaseIterable {
    case mlx
    case fm
    case noProvider = "none"
}

/// Why the preferred provider did not answer. There is no `duringShow`: paste is disabled
/// during a show (R95).
public enum PasteFallback: String, Sendable, CaseIterable {
    case noFallback = "none"
    case aiOff
    case notInstalled
    case fmOff
    case fmNotReady
    case fmIneligible
    case unsupportedLang
    case guardrail
    case decoding
    case overBudget
    case busy
    case timeout
    case other
}

public enum PasteOutcome: String, Sendable, CaseIterable {
    case accepted
    case cancelled
    /// A batch file left unticked (R96).
    case unticked
}

/// The AI refinement's wall time.
public enum LatencyBucket: String, LogBucket {
    case noLatency = "none"
    case under1s = "<1s"
    case from1to3s = "1-3s"
    case from3to10s = "3-10s"
    case from10to30s = "10-30s"
    case over30s = "30s+"

    /// `nil` when no model was asked.
    public init(seconds: TimeInterval?) {
        guard let seconds else {
            self = .noLatency
            return
        }
        switch seconds {
        case ..<1: self = .under1s
        case 1 ..< 3: self = .from1to3s
        case 3 ..< 10: self = .from3to10s
        case 10 ..< 30: self = .from10to30s
        default: self = .over30s
        }
    }
}

/// The edit distance between the AI-decided labels and metadata and the accepted ones.
public enum CorrectionBucket: String, LogBucket {
    case noCorrection = "none"
    case small
    case medium
    case large

    /// `changes` is the edit distance (0 none, 1 small, 2-3 medium, 4+ large).
    public init(changes: Int) {
        switch changes {
        case ..<1: self = .noCorrection
        case 1: self = .small
        case 2 ..< 4: self = .medium
        default: self = .large
        }
    }
}

// MARK: - Row 20: Segue.AI.modelDownload

public struct ModelDownloadSummary: Sendable, Hashable {
    public var result: ModelDownloadResult
    public var kind: ModelDownloadKind
    public var duration: DownloadDurationBucket
    /// The Mac has less than 16 GB of memory (R68).
    public var ramUnder16: Bool

    public init(
        result: ModelDownloadResult,
        kind: ModelDownloadKind,
        duration: DownloadDurationBucket,
        ramUnder16: Bool,
    ) {
        self.result = result
        self.kind = kind
        self.duration = duration
        self.ramUnder16 = ramUnder16
    }
}

public enum ModelDownloadResult: String, Sendable, CaseIterable {
    case completed
    case cancelled
    case network
    case checksum
    case disk
    case other
}

public enum ModelDownloadKind: String, Sendable, CaseIterable {
    case curated
    /// A Personal-only Advanced model (R62).
    case custom
}

/// How long a model download ran.
public enum DownloadDurationBucket: String, LogBucket {
    case under1m = "<1m"
    case from1to5m = "1-5m"
    case from5to15m = "5-15m"
    case from15to60m = "15-60m"
    case over60m = "60m+"

    public init(seconds: TimeInterval) {
        switch seconds / 60 {
        case ..<1: self = .under1m
        case 1 ..< 5: self = .from1to5m
        case 5 ..< 15: self = .from5to15m
        case 15 ..< 60: self = .from15to60m
        default: self = .over60m
        }
    }
}

// MARK: - Row 21: Segue.AI.assistantUsed

public struct AssistantUsedSummary: Sendable, Hashable {
    public var context: AssistantContext
    /// Chips the code lexicon produced.
    public var lexiconChips: SmallBucket
    /// Model-suggested chips shown.
    public var suggestedShown: SmallBucket
    /// Model-suggested chips the user accepted.
    public var suggestedAccepted: SmallBucket
    public var provider: AIProviderUsed
    /// The set was rebuilt from the same request.
    public var rebuilt: Bool
    /// P8-8 section 8: the request held an artist chip ("by arijit"), a Movie / Album chip
    /// ("from kalank"), included or excluded.
    public var artistChips: Bool
    public var albumChips: Bool

    public init(
        context: AssistantContext,
        lexiconChips: SmallBucket,
        suggestedShown: SmallBucket,
        suggestedAccepted: SmallBucket,
        provider: AIProviderUsed,
        rebuilt: Bool,
        artistChips: Bool = false,
        albumChips: Bool = false,
    ) {
        self.context = context
        self.lexiconChips = lexiconChips
        self.suggestedShown = suggestedShown
        self.suggestedAccepted = suggestedAccepted
        self.provider = provider
        self.rebuilt = rebuilt
        self.artistChips = artistChips
        self.albumChips = albumChips
    }
}

public enum AssistantContext: String, Sendable, CaseIterable {
    case builder
    case library
    case stage
}

// MARK: - Row 22: Segue.AI.smartFilterUsed

public enum SmartFilterAction: String, Sendable, CaseIterable {
    case created
    case applied
    case assistantInput
}

// MARK: - Rendering

extension AnalyticsEvent {
    /// The parameters of rows 19-22 (empty for every other row).
    var aiParams: [String: String] {
        switch self {
        case let .aiPasteFinished(summary):
            [
                "segue.source": summary.source.rawValue,
                "segue.provider": summary.provider.rawValue,
                "segue.fallback": summary.fallback.rawValue,
                "segue.latency": summary.latency.rawValue,
                "segue.outcome": summary.outcome.rawValue,
                "segue.correction": summary.correction.rawValue,
                "segue.romanHindi": String(summary.romanHindi),
            ]
        case let .aiModelDownload(summary):
            [
                "segue.result": summary.result.rawValue,
                "segue.kind": summary.kind.rawValue,
                "segue.duration": summary.duration.rawValue,
                "segue.ramUnder16": String(summary.ramUnder16),
            ]
        case let .aiAssistantUsed(summary):
            [
                "segue.context": summary.context.rawValue,
                "segue.lexiconChips": summary.lexiconChips.rawValue,
                "segue.suggestedShown": summary.suggestedShown.rawValue,
                "segue.suggestedAccepted": summary.suggestedAccepted.rawValue,
                "segue.provider": summary.provider.rawValue,
                "segue.rebuilt": String(summary.rebuilt),
                "segue.artistChips": String(summary.artistChips),
                "segue.albumChips": String(summary.albumChips),
            ]
        case let .aiSmartFilterUsed(action, conditions):
            ["segue.action": action.rawValue, "segue.conditions": conditions.rawValue]
        default:
            [:]
        }
    }
}
