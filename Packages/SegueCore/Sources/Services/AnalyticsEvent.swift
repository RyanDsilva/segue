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
    /// Row 5: a new song (daily per source and lookalike flag). `nearDuplicate`: a
    /// created song carried the "looks like a song in your library" warning (R163).
    case songCreated(SongSource, nearDuplicate: Bool = false)
    // Flat parameters, like every row: the closed vocabulary maps each one to one key.
    // swiftlint:disable enum_case_associated_values_count
    /// Row 6: one import operation.
    case songImported(
        method: ImportMethod,
        files: SmallBucket,
        outcome: ImportOutcome,
        nonUTF8: Bool,
        // At least one imported song carried the "looks like a song in your library"
        // warning (P8-1, R154).
        nearDuplicate: Bool = false,
    )
    // swiftlint:enable enum_case_associated_values_count
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
    /// Row 14: a Help menu item or an in-app Help button (daily per item, route and origin).
    /// `via`: whether the offline Help Book or the web guide opened (P9-5 6; nil for items
    /// that open neither). `from`: where Report a Problem was chosen (nil for other items).
    case helpOpened(HelpItem, via: HelpRoute? = nil, from: HelpOrigin? = nil)
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
    /// Row 23 (P3-17): a section note was added, moved, toggled or deleted (daily per action,
    /// kind and placement).
    case notesEdited(NotesEditedSummary)
    /// Row 24 (P8-5): a Return in the set composer, and a composer session that added rows.
    case setlistComposed(ComposerSummary)
    case setlistComposerSession(songs: SmallBucket, cycles: SmallBucket)
    /// Row 25 (P8-4b 8.12): a walk-up chosen in the picker (daily per kind, rank and feel).
    case walkUpPicked(WalkUpPickSummary)
    /// Row 26 (P8-7 15): a fill saved in the fill editor (daily per family, rank, edited).
    case fillSaved(FillSavedSummary)
    /// Row 27 (P8-7 15): a Tap Timing review kept or discarded (per occurrence).
    case timingTapCaptured(TapCapturedSummary)
    /// Row 28 (P8-7 15): a key change confirmed from the chip, dismissed, or inserted from
    /// the menus (daily per action and interval).
    case timingKeyChange(action: KeyChangeAction, interval: KeyChangeInterval)
    /// Row 29 (P8-8 8): an accepted song whose artist a paste or import split (daily).
    case songArtistSplit(ArtistSplitSummary)
    /// Row 30 (P8-8 8): the builder left a setlist with songs (daily per target).
    case setlistTimed(SetlistTimedSummary)
    /// Row 32 (P9-3 14): a builder medley action, daily per (action, entry);
    /// `members` is the medley's size after the action.
    case setlistMedley(action: MedleyAction, members: SmallBucket, entry: MedleyEntryPoint)
    /// Row 31 (P9-1 spec 11): one per PDF preview sheet closed.
    case pdfExported(PDFExportSummary)
}

// MARK: - Grouped parameters (cases with more than four values)

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
    /// The folder is in iCloud Drive or a CloudStorage service (P9-6 5.4); which service is
    /// never sent.
    case fileSyncFolder
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

public enum FeatureContext: String, Sendable, CaseIterable {
    case library
    case editor
    case stage
    case builder
    case settings
    case screen
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
    /// The PDF preview sheet's Help button (P9-1, R181).
    case pdf
    /// An in-app Help button or a tip's Learn More (P9-5 6).
    case contextHelp
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
    /// A section note edit whose note was no longer in the song (P3-17: stale edits after
    /// the move to stable IDs; should stay near zero).
    case sectionNoteGone
    /// The bundled sound bank failed to load and a fallback played instead (P8-6 8.1;
    /// once per launch).
    case soundBankLoad
    /// A PDF export's render or save failed (P9-1 spec 6.2).
    case pdfExport
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
        case .songArtistSplit, .songCreated, .songDeleted, .songImported: "Song"
        case .featureUsed: "Feature"
        case .editorChordPalette, .editorOpened: "Editor"
        case .setlistComposed, .setlistComposerSession, .setlistCreated, .setlistMedley,
             .setlistTimed: "Setlist"
        case .showEnded, .showStarted: "Show"
        case .milestoneReached: "Milestone"
        case .helpOpened: "Help"
        case .feedbackSent: "Feedback"
        case .errorOccurred: "Error"
        case .searchPerformed: "Search"
        case .aiAssistantUsed, .aiModelDownload, .aiPasteFinished, .aiSmartFilterUsed: "AI"
        case .notesEdited: "Notes"
        case .fillSaved, .walkUpPicked: "Bass"
        case .timingKeyChange, .timingTapCaptured: "Timing"
        case .pdfExported: "Export"
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
        case .notesEdited: "edited"
        case .setlistComposed: "composed"
        case .setlistComposerSession: "composerSession"
        case .walkUpPicked: "walkUpPicked"
        case .fillSaved: "fillSaved"
        case .timingTapCaptured: "tapCaptured"
        case .timingKeyChange: "keyChange"
        case .songArtistSplit: "artistSplit"
        case .setlistTimed: "timed"
        case .setlistMedley: "medley"
        case .pdfExported: "pdf"
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
                "segue.noTempo": snapshot.noTempo.rawValue,
            ]
        case let .libraryCreated(location):
            ["segue.location": location.rawValue]
        case let .songCreated(source, nearDuplicate):
            [
                "segue.source": source.rawValue,
                "segue.nearDuplicate": String(nearDuplicate),
            ]
        case let .songImported(method, files, outcome, nonUTF8, nearDuplicate):
            [
                "segue.method": method.rawValue,
                "segue.files": files.rawValue,
                "segue.outcome": outcome.rawValue,
                "segue.nonUTF8": String(nonUTF8),
                "segue.nearDuplicate": String(nearDuplicate),
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
                "segue.singer": String(summary.singerView),
            ]
        case let .milestoneReached(milestone, days):
            ["segue.milestone": milestone.rawValue, "segue.daysSinceFirstLaunch": days.rawValue]
        case let .helpOpened(item, via, from):
            Self.helpParams(item, via: via, from: from)
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
        case let .notesEdited(summary):
            [
                "segue.action": summary.action.rawValue,
                "segue.kind": summary.kind.rawValue,
                "segue.placement": summary.placement.rawValue,
                "segue.entry": summary.entry.rawValue,
                "segue.repeatHint": String(summary.repeatHint),
            ]
        case .setlistComposed, .setlistComposerSession: composerParams
        case let .walkUpPicked(summary):
            [
                "segue.kind": summary.kind.rawValue,
                "segue.rank": summary.rank.rawValue,
                "segue.genre": summary.genre.rawValue,
            ]
        case let .fillSaved(summary):
            summary.params
        case let .timingTapCaptured(summary):
            summary.params
        case let .timingKeyChange(action, interval):
            ["segue.action": action.rawValue, "segue.interval": interval.rawValue]
        case let .songArtistSplit(summary): summary.params
        case let .setlistTimed(summary): summary.params
        case .setlistMedley: medleyParams
        case let .pdfExported(summary): summary.params
        }
    }
}
