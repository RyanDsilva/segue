import Foundation

/// The closed analytics vocabulary (spec section 5, rows 1-18; row 0, the session signal,
/// is added by the ingest client itself).
///
/// Rules this type enforces structurally:
/// - every associated value is an enum, a `Bool`, a bucket or a struct of those; there is no
///   `String` anywhere, so titles, lyrics, names, paths, queries and error messages cannot be
///   expressed;
/// - signal names are `Segue.<Area>.<event>`, parameter keys `segue.<camelCase>`, and every
///   rendered value matches `^[A-Za-z0-9+<>._-]{1,24}$`.
///
/// Extending the vocabulary is a reviewed code change under these rules.
public enum AnalyticsEvent: Sendable, Hashable {
    /// Row 1: analytics were just granted.
    case analyticsEnabled(ConsentSource)
    /// Row 2: launch, after the library resolves (daily).
    case appLaunched(
        daysSinceFirstLaunch: DaysBucket,
        flavor: AppFlavor,
        library: LaunchLibraryState,
    )
    /// Row 3: after the library opens (daily).
    case librarySnapshot(LibrarySnapshot)
    /// Row 4: a library was chosen.
    case libraryCreated(LibraryLocation)
    /// Row 5: a new song (daily per source).
    case songCreated(SongSource)
    /// Row 6: one import operation.
    case songImported(
        method: ImportMethod,
        files: SmallBucket,
        outcome: ImportOutcome,
        nonUTF8: Bool,
    )
    /// Row 7: a Delete Song (daily).
    case songDeleted(count: SmallBucket)
    /// Row 8: first use of a feature in a context each day.
    case featureUsed(FeatureKey, FeatureContext)
    /// Row 9: the editor opened (daily per mode).
    case editorOpened(EditorMode)
    /// Row 10: a setlist was created (daily per source).
    case setlistCreated(SetlistSource)
    /// Row 11: the stage was entered.
    case showStarted(kind: AnalyticsShowKind, songs: SmallBucket, resumed: Bool, shortcutsOn: Bool)
    /// Row 12: a show finished.
    case showEnded(ShowSummary)
    /// Row 13: an activation milestone, once per install.
    case milestoneReached(Milestone, daysSinceFirstLaunch: DaysBucket)
    /// Row 14: a Help menu item (daily per item).
    case helpOpened(HelpItem)
    /// Row 15: a bug report left the Mac.
    case feedbackSent(FeedbackSentSummary)
    /// Row 16: an error surfaced to the user (daily per code).
    case errorOccurred(ErrorCode)
    /// Row 17: search results shown (daily per context and tier). The query is never recorded.
    case searchPerformed(context: SearchContext, matchTier: SearchMatchTier, results: SmallBucket)
    /// Row 18: a chord palette chip was armed or an armed chord placed (daily per action).
    case editorChordPalette(action: PaletteAction, chords: SmallBucket)
    /// Row 19 (phase 3, R74/R98): one pasted or converted song left the review sheet (one
    /// per file in a batch).
    case aiPasteFinished(PasteFinishedSummary)
    /// Row 20 (R74): a model download ended.
    case aiModelDownload(ModelDownloadSummary)
    /// Row 21 (R74): the set assistant built or rebuilt a set.
    case aiAssistantUsed(AssistantUsedSummary)
    /// Row 22 (R74): a smart filter was created, applied or filled from the assistant.
    case aiSmartFilterUsed(action: SmartFilterAction, conditions: SmallBucket)
}

// MARK: - Grouped parameters (cases with more than four values)

/// Row 3 parameters.
public struct LibrarySnapshot: Sendable, Hashable {
    public var songs: SongBucket
    public var setlists: SmallBucket
    public var gigs: SmallBucket
    public var welcomeSongsLeft: WelcomeSongsLeft
    public var customShapes: Bool

    public init(
        songs: SongBucket,
        setlists: SmallBucket,
        gigs: SmallBucket,
        welcomeSongsLeft: WelcomeSongsLeft,
        customShapes: Bool,
    ) {
        self.songs = songs
        self.setlists = setlists
        self.gigs = gigs
        self.welcomeSongsLeft = welcomeSongsLeft
        self.customShapes = customShapes
    }
}

/// Row 12 parameters.
public struct ShowSummary: Sendable, Hashable {
    public var kind: AnalyticsShowKind
    public var duration: DurationBucket
    public var played: SmallBucket
    public var skipped: SmallBucket
    public var requestsUsed: Bool
    public var autoScrollUsed: Bool
    public var reordered: Bool
    public var endedBy: ShowEndReason

    public init(
        kind: AnalyticsShowKind,
        duration: DurationBucket,
        played: SmallBucket,
        skipped: SmallBucket,
        requestsUsed: Bool,
        autoScrollUsed: Bool,
        reordered: Bool,
        endedBy: ShowEndReason,
    ) {
        self.kind = kind
        self.duration = duration
        self.played = played
        self.skipped = skipped
        self.requestsUsed = requestsUsed
        self.autoScrollUsed = autoScrollUsed
        self.reordered = reordered
        self.endedBy = endedBy
    }
}

/// Row 15 parameters.
public struct FeedbackSentSummary: Sendable, Hashable {
    public var transport: FeedbackTransport
    public var logs: Bool
    public var metricKit: Bool
    public var song: Bool
    public var email: Bool

    public init(
        transport: FeedbackTransport,
        logs: Bool,
        metricKit: Bool,
        song: Bool,
        email: Bool,
    ) {
        self.transport = transport
        self.logs = logs
        self.metricKit = metricKit
        self.song = song
        self.email = email
    }
}

// MARK: - Parameter values

/// Where a consent decision was made; also row 1's `segue.source`.
public enum ConsentSource: String, Sendable, Hashable, Codable, CaseIterable {
    case prompt
    case welcome
    case settings
}

public enum AppFlavor: String, Sendable, CaseIterable {
    case appStore
    case personal
}

public enum LaunchLibraryState: String, Sendable, CaseIterable {
    case open
    case chooser
    case accessLost
}

/// Raw value `none` is the spec's value; the case name avoids clashing with `Optional.none`.
public enum WelcomeSongsLeft: String, Sendable, CaseIterable {
    case noneLeft = "none"
    case some
    case all
}

public enum LibraryLocation: String, Sendable, CaseIterable {
    case suggestedMusicFolder
    case otherFolder
    case existingLibrary
}

public enum SongSource: String, Sendable, CaseIterable {
    case newSong
    case `import`
}

public enum ImportMethod: String, Sendable, CaseIterable {
    case dragDrop
    case fileMenu
    case openWith
}

public enum ImportOutcome: String, Sendable, CaseIterable {
    case all
    case partial
    case nothingImported = "none"
}

/// Row 8 `segue.feature`. Chord palette use is row 18, not a key here.
public enum FeatureKey: String, Sendable, CaseIterable {
    case transpose
    case capo
    case nashville
    case diagrams
    case instrumentPiano
    case tuningChange
    case applyTransposeToSource
    case editorModeSwitch
    case search
    case filterChips
    case setlistEdit
    case setlistTarget
    case autoScroll
    case stageSearch
    case playNow
    case requests
    case columnsCycle
    case stageZoom
    case collapseRepeats
    case gigLogEdit
    case liveSettings
    case shapeEditor
    case showInFinder
    case undoInBuilder
    /// The song card's Time it timer was stopped into a length (R91).
    case timeIt
    /// The stage metronome was switched on (R90, P3-14).
    case metronome
}

public enum FeatureContext: String, Sendable, CaseIterable {
    case library
    case editor
    case stage
    case builder
    case settings
}

public enum EditorMode: String, Sendable, CaseIterable {
    case visual
    case text
}

public enum SetlistSource: String, Sendable, CaseIterable {
    case new
    case duplicate
    case welcome
}

public enum AnalyticsShowKind: String, Sendable, CaseIterable {
    case gig
    case rehearsal
}

public enum ShowEndReason: String, Sendable, CaseIterable {
    case endShow
    case quit
    case closedOnRelaunch
}

public enum Milestone: String, Sendable, CaseIterable {
    case firstSong
    case firstImport
    case firstSetlist
    case firstRehearsal
    case firstGig
    case firstCompletedGig
    case tenSongs
    case fiftySongs
}

public enum HelpItem: String, Sendable, CaseIterable {
    case help
    case keyboardShortcuts
    case whatsNew
    case reportProblem
    case requestFeature
    case privacyPolicy
    case terms
}

public enum FeedbackTransport: String, Sendable, CaseIterable {
    case sentry
    case email
    case file
}

/// Errors are reported as these codes only, never as messages.
public enum ErrorCode: String, Sendable, CaseIterable {
    case libraryAccessLost
    case libraryOpenFailed
    case indexRebuildFailed
    case saveConflict
    case saveFailed
    case importFailed
    case showStartFailed
    case showResumeFailed
    case shapeLibraryUnreadable
    case bindingsUnreadable
    case other
}

public enum SearchContext: String, Sendable, CaseIterable {
    case library
    case stage
    case builder
}

/// The `LibraryStore.search` tier that produced the first result (row 17).
public enum SearchMatchTier: String, Sendable, CaseIterable {
    case exact
    case spellingVariant
    case looseVariant
    case fuzzy
    case noResults = "none"
}

public enum PaletteAction: String, Sendable, CaseIterable {
    case armed
    case placed
}

// MARK: - Rendering

/// A rendered analytics signal: a `Segue.*` name and flat string parameters. Only
/// `AnalyticsEvent.render()` can make one, so an adapter can never be handed free text.
public struct AnalyticsSignal: Sendable, Hashable {
    public let name: String
    public let params: [String: String]
}

extension AnalyticsEvent {
    /// The signal this event sends.
    public func render() -> AnalyticsSignal {
        AnalyticsSignal(name: "Segue.\(area).\(eventName)", params: params)
    }

    var area: String {
        switch self {
        case .analyticsEnabled: "Privacy"
        case .appLaunched: "App"
        case .libraryCreated, .librarySnapshot: "Library"
        case .songCreated, .songDeleted, .songImported: "Song"
        case .featureUsed: "Feature"
        case .editorChordPalette, .editorOpened: "Editor"
        case .setlistCreated: "Setlist"
        case .showEnded, .showStarted: "Show"
        case .milestoneReached: "Milestone"
        case .helpOpened: "Help"
        case .feedbackSent: "Feedback"
        case .errorOccurred: "Error"
        case .searchPerformed: "Search"
        case .aiAssistantUsed, .aiModelDownload, .aiPasteFinished, .aiSmartFilterUsed: "AI"
        }
    }

    var eventName: String {
        switch self {
        case .analyticsEnabled: "analyticsEnabled"
        case .appLaunched: "launched"
        case .librarySnapshot: "snapshot"
        case .libraryCreated, .setlistCreated, .songCreated: "created"
        case .songImported: "imported"
        case .songDeleted: "deleted"
        case .featureUsed: "used"
        case .editorOpened, .helpOpened: "opened"
        case .showStarted: "started"
        case .showEnded: "ended"
        case .milestoneReached: "reached"
        case .feedbackSent: "sent"
        case .errorOccurred: "occurred"
        case .searchPerformed: "performed"
        case .editorChordPalette: "chordPalette"
        case .aiPasteFinished: "pasteFinished"
        case .aiModelDownload: "modelDownload"
        case .aiAssistantUsed: "assistantUsed"
        case .aiSmartFilterUsed: "smartFilterUsed"
        }
    }

    /// One flat switch over the vocabulary reads best; splitting it would hide the table.
    var params: [String: String] {
        switch self {
        case let .analyticsEnabled(source):
            ["segue.source": source.rawValue]
        case let .appLaunched(days, flavor, library):
            [
                "segue.daysSinceFirstLaunch": days.rawValue,
                "segue.flavor": flavor.rawValue,
                "segue.libraryState": library.rawValue,
            ]
        case let .librarySnapshot(snapshot):
            [
                "segue.songs": snapshot.songs.rawValue,
                "segue.setlists": snapshot.setlists.rawValue,
                "segue.gigs": snapshot.gigs.rawValue,
                "segue.welcomeSongsLeft": snapshot.welcomeSongsLeft.rawValue,
                "segue.customShapes": String(snapshot.customShapes),
            ]
        case let .libraryCreated(location):
            ["segue.location": location.rawValue]
        case let .songCreated(source):
            ["segue.source": source.rawValue]
        case let .songImported(method, files, outcome, nonUTF8):
            [
                "segue.method": method.rawValue,
                "segue.files": files.rawValue,
                "segue.outcome": outcome.rawValue,
                "segue.nonUTF8": String(nonUTF8),
            ]
        case let .songDeleted(count):
            ["segue.count": count.rawValue]
        case let .featureUsed(feature, context):
            ["segue.feature": feature.rawValue, "segue.context": context.rawValue]
        case let .editorOpened(mode):
            ["segue.mode": mode.rawValue]
        case let .setlistCreated(source):
            ["segue.source": source.rawValue]
        case let .showStarted(kind, songs, resumed, shortcutsOn):
            [
                "segue.kind": kind.rawValue,
                "segue.songs": songs.rawValue,
                "segue.resumed": String(resumed),
                "segue.shortcutsOn": String(shortcutsOn),
            ]
        case let .showEnded(summary):
            [
                "segue.kind": summary.kind.rawValue,
                "segue.duration": summary.duration.rawValue,
                "segue.played": summary.played.rawValue,
                "segue.skipped": summary.skipped.rawValue,
                "segue.requestsUsed": String(summary.requestsUsed),
                "segue.autoScrollUsed": String(summary.autoScrollUsed),
                "segue.reordered": String(summary.reordered),
                "segue.endedBy": summary.endedBy.rawValue,
            ]
        case let .milestoneReached(milestone, days):
            ["segue.milestone": milestone.rawValue, "segue.daysSinceFirstLaunch": days.rawValue]
        case let .helpOpened(item):
            ["segue.item": item.rawValue]
        case let .feedbackSent(summary):
            [
                "segue.transport": summary.transport.rawValue,
                "segue.logs": String(summary.logs),
                "segue.metricKit": String(summary.metricKit),
                "segue.song": String(summary.song),
                "segue.email": String(summary.email),
            ]
        case let .errorOccurred(code):
            ["segue.code": code.rawValue]
        case let .searchPerformed(context, tier, results):
            [
                "segue.context": context.rawValue,
                "segue.matchTier": tier.rawValue,
                "segue.results": results.rawValue,
            ]
        case let .editorChordPalette(action, chords):
            ["segue.action": action.rawValue, "segue.chords": chords.rawValue]
        case .aiAssistantUsed, .aiModelDownload, .aiPasteFinished, .aiSmartFilterUsed:
            aiParams
        }
    }
}
