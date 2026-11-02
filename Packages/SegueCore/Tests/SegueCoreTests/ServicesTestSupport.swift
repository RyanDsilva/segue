import Foundation
import Services
import Support

/// Shared fixtures for the services suites: a temp directory, a throwaway defaults suite,
/// and a sample of the whole analytics vocabulary that covers every parameter value.
struct ServicesSandbox {
    let directory: URL
    let suiteName: String
    let log: RecordingLog
    let factory: RecordingServicesFactory
    let clock = ManualClock(start: Date(timeIntervalSince1970: 1_792_224_000)) // 2026-10-17

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "segue-services-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "segue.services.tests.\(UUID().uuidString)"
        log = RecordingLog(url: directory.appending(path: "services.jsonl"))
        factory = RecordingServicesFactory(log: log)
    }

    func throttle() -> AnalyticsThrottle {
        AnalyticsThrottle(
            suiteName: suiteName,
            clock: clock,
            timeZone: { TimeZone(identifier: "America/Los_Angeles") ?? .gmt },
        )
    }

    func hub(_ consent: ConsentState) -> ServicesHub {
        ServicesHub(factory: factory, consent: consent, throttle: throttle())
    }

    /// Recorded lines of one kind.
    func entries(_ kind: String) -> [[String: Any]] {
        log.entries().filter { $0["kind"] as? String == kind }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

extension ConsentState {
    static let date = Date(timeIntervalSince1970: 1_792_224_000)
    static let allGranted = ConsentState(analytics: .granted(date), crashReports: .granted(date))
    static let allDeclined = ConsentState(
        analytics: .declined(date),
        crashReports: .declined(date),
    )
    static let analyticsOnly = ConsentState(
        analytics: .granted(date),
        crashReports: .declined(date),
    )
    static let crashOnly = ConsentState(analytics: .declined(date), crashReports: .granted(date))
}

/// Every event case with every parameter value appearing at least once.
enum VocabularySample {
    static var all: [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        events += ConsentSource.allCases.map(AnalyticsEvent.analyticsEnabled)
        for days in DaysBucket.allCases {
            for flavor in AppFlavor.allCases {
                for state in LaunchLibraryState.allCases {
                    events.append(.appLaunched(
                        daysSinceFirstLaunch: days,
                        flavor: flavor,
                        library: state,
                    ))
                }
            }
        }
        events += snapshots.map(AnalyticsEvent.librarySnapshot)
        events += LibraryLocation.allCases.map(AnalyticsEvent.libraryCreated)
        events += SongSource.allCases.map { AnalyticsEvent.songCreated($0) }
        events += SongSource.allCases.map { AnalyticsEvent.songCreated($0, nearDuplicate: true) }
        for method in ImportMethod.allCases {
            for files in SmallBucket.allCases {
                for outcome in ImportOutcome.allCases {
                    events.append(.songImported(
                        method: method,
                        files: files,
                        outcome: outcome,
                        nonUTF8: true,
                    ))
                    events.append(.songImported(
                        method: method,
                        files: files,
                        outcome: outcome,
                        nonUTF8: false,
                    ))
                    events.append(.songImported(
                        method: method,
                        files: files,
                        outcome: outcome,
                        nonUTF8: false,
                        nearDuplicate: true,
                    ))
                }
            }
        }
        events += SmallBucket.allCases.map { AnalyticsEvent.songDeleted(count: $0) }
        for feature in FeatureKey.allCases {
            events += FeatureContext.allCases.map { AnalyticsEvent.featureUsed(feature, $0) }
        }
        events += EditorMode.allCases.map(AnalyticsEvent.editorOpened)
        events += SetlistSource.allCases.map(AnalyticsEvent.setlistCreated)
        for kind in AnalyticsShowKind.allCases {
            for songs in SmallBucket.allCases {
                for flags in [(false, false), (true, false), (false, true), (true, true)] {
                    events.append(.showStarted(
                        kind: kind,
                        songs: songs,
                        resumed: flags.0,
                        shortcutsOn: flags.1,
                    ))
                }
            }
        }
        events += showSummaries.map(AnalyticsEvent.showEnded)
        for milestone in Milestone.allCases {
            events += DaysBucket.allCases.map { days in
                AnalyticsEvent.milestoneReached(milestone, daysSinceFirstLaunch: days)
            }
        }
        events += HelpItem.allCases.map { AnalyticsEvent.helpOpened($0) }
        events += HelpRoute.allCases.map { AnalyticsEvent.helpOpened(.contextHelp, via: $0) }
        events += HelpOrigin.allCases.map { AnalyticsEvent.helpOpened(.reportProblem, from: $0) }
        for page in HelpPage.allCases {
            events.append(.helpOpened(.contextHelp, via: .book, page: page))
        }
        for transport in FeedbackTransport.allCases {
            for bits in 0 ..< 16 {
                events.append(.feedbackSent(FeedbackSentSummary(
                    transport: transport,
                    logs: bits & 1 != 0,
                    metricKit: bits & 2 != 0,
                    song: bits & 4 != 0,
                    email: bits & 8 != 0,
                )))
            }
        }
        events += ErrorCode.allCases.map(AnalyticsEvent.errorOccurred)
        for context in SearchContext.allCases {
            for tier in SearchMatchTier.allCases {
                events += SmallBucket.allCases.map {
                    AnalyticsEvent.searchPerformed(context: context, matchTier: tier, results: $0)
                }
            }
        }
        for action in PaletteAction.allCases {
            events += SmallBucket.allCases.map { chords in
                AnalyticsEvent.editorChordPalette(action: action, chords: chords)
            }
        }
        events += AISample.all
        let actions = NoteEditAction.allCases, kinds = NoteKind.allCases
        let placements = NotePlacementKind.allCases, entries = NoteEntry.allCases
        for row in 0 ..< max(actions.count, kinds.count, placements.count, entries.count) {
            events.append(.notesEdited(NotesEditedSummary(
                action: actions[row % actions.count],
                kind: kinds[row % kinds.count],
                placement: placements[row % placements.count],
                entry: entries[row % entries.count],
                repeatHint: row.isMultiple(of: 2),
            )))
        }
        events += composerEvents
        let pickKinds = WalkUpPickKind.allCases, ranks = WalkUpRank.allCases
        let feels = WalkUpFeel.allCases
        events += (0 ..< max(pickKinds.count, ranks.count, feels.count)).map { row in
            .walkUpPicked(WalkUpPickSummary(
                kind: pickKinds[row % pickKinds.count],
                rank: ranks[row % ranks.count],
                genre: feels[row % feels.count],
            ))
        }
        events += timingEvents
        events += fillEvents
        events += artistSplitEvents
        events += setlistTimedEvents
        events += pdfExportEvents
        events += medleyEvents
        return events
    }

    /// Row 32 (P9-3): every medley action and entry point at least once.
    private static var medleyEvents: [AnalyticsEvent] {
        let actions = MedleyAction.allCases, entries = MedleyEntryPoint.allCases
        return (0 ..< max(actions.count, entries.count)).map { row in
            .setlistMedley(
                action: actions[row % actions.count],
                members: SmallBucket(row + 1),
                entry: entries[row % entries.count],
            )
        }
    }

    /// Row 26 (P8-7): every family, rank, view, feel and "Shows on" at least once.
    private static var fillEvents: [AnalyticsEvent] {
        let families = FillSavedFamily.allCases, ranks = FillSavedRank.allCases
        let views = FillSavedView.allCases, feels = WalkUpFeel.allCases
        let shows = FillSavedShows.allCases
        return (0 ..< max(families.count, ranks.count, views.count, feels.count)).map { row in
            .fillSaved(FillSavedSummary(
                family: families[row % families.count],
                rank: ranks[row % ranks.count],
                edited: row.isMultiple(of: 2),
                view: views[row % views.count],
                chords: SmallBucket(row + 2),
                keyChange: row.isMultiple(of: 3),
                genre: feels[row % feels.count],
                shows: shows[row % shows.count],
                estimated: !row.isMultiple(of: 2),
            ))
        }
    }

    /// Row 30 (P8-8): every target at least once.
    private static var setlistTimedEvents: [AnalyticsEvent] {
        SetlistTimedTarget.allCases.enumerated().map { index, target in
            .setlistTimed(SetlistTimedSummary(
                songs: SmallBucket(index + 1),
                noTempo: SmallBucket(index),
                noChords: SmallBucket(0),
                arranged: SmallBucket(index),
                estimatedOnly: index.isMultiple(of: 2),
                target: target,
                medleys: SmallBucket(index),
                medleyUnknown: index.isMultiple(of: 2),
            ))
        }
    }

    /// Row 29 (P8-8): every source, separator and outcome at least once.
    private static var artistSplitEvents: [AnalyticsEvent] {
        let sources = ArtistSplitSource.allCases, separators = ArtistSplitSeparator.allCases
        let outcomes = ArtistSplitOutcome.allCases
        return (0 ..< max(sources.count, separators.count, outcomes.count)).map { row in
            .songArtistSplit(ArtistSplitSummary(
                source: sources[row % sources.count],
                parts: SmallBucket(row + 2),
                separator: separators[row % separators.count],
                outcome: outcomes[row % outcomes.count],
            ))
        }
    }

    /// Rows 27 and 28 (P8-7): every tap mode, outcome and key-change action and interval.
    private static var timingEvents: [AnalyticsEvent] {
        let modes = TapCaptureMode.allCases, outcomes = TapCaptureOutcome.allCases
        var events = (0 ..< max(modes.count, outcomes.count)).map { row in
            AnalyticsEvent.timingTapCaptured(TapCapturedSummary(
                mode: modes[row % modes.count],
                outcome: outcomes[row % outcomes.count],
                chords: SmallBucket(row * 3),
                skipped: SmallBucket(row),
                tempoSet: row.isMultiple(of: 2),
            ))
        }
        let actions = KeyChangeAction.allCases, intervals = KeyChangeInterval.allCases
        events += (0 ..< max(actions.count, intervals.count)).map { row in
            .timingKeyChange(
                action: actions[row % actions.count],
                interval: intervals[row % intervals.count],
            )
        }
        return events
    }

    /// Row 24 (P8-5): every composer action, tier, form and entry at least once.
    private static var composerEvents: [AnalyticsEvent] {
        let actions = ComposerAction.allCases, tiers = ComposerTier.allCases
        let forms = ComposerForm.allCases, entries = ComposerEntry.allCases
        var events = (0 ..< max(actions.count, tiers.count, forms.count)).map { row in
            AnalyticsEvent.setlistComposed(ComposerSummary(
                action: actions[row % actions.count],
                tier: tiers[row % tiers.count],
                form: forms[row % forms.count],
                alternative: row.isMultiple(of: 2),
                key: row.isMultiple(of: 3),
                entry: entries[row % entries.count],
                artistWords: row.isMultiple(of: 4),
                members: actions[row % actions.count] == .medley ? SmallBucket(row + 2) : nil,
            ))
        }
        events += SmallBucket.allCases.map { bucket in
            .setlistComposerSession(songs: bucket, cycles: bucket)
        }
        return events
    }

    private static let baseSnapshot = LibrarySnapshot(
        songs: .zero,
        setlists: .zero,
        gigs: .zero,
        welcomeSongsLeft: .all,
        customShapes: false,
    )

    private static var snapshots: [LibrarySnapshot] {
        var result: [LibrarySnapshot] = []
        result += SongBucket.allCases.map { var value = baseSnapshot
            value.songs = $0
            return value
        }
        result += SmallBucket.allCases.map { var value = baseSnapshot
            value.setlists = $0
            return value
        }
        result += SmallBucket.allCases.map { var value = baseSnapshot
            value.gigs = $0
            return value
        }
        result += WelcomeSongsLeft.allCases.map { var value = baseSnapshot
            value.welcomeSongsLeft = $0
            return value
        }
        result += [true, false].map { var value = baseSnapshot
            value.customShapes = $0
            return value
        }
        return result
    }

    private static let baseSummary = ShowSummary(
        kind: .gig,
        duration: .under15m,
        played: .zero,
        skipped: .zero,
        requestsUsed: false,
        autoScrollUsed: false,
        reordered: false,
        endedBy: .endShow,
    )

    private static var showSummaries: [ShowSummary] {
        var result: [ShowSummary] = []
        result += AnalyticsShowKind.allCases.map { var value = baseSummary
            value.kind = $0
            return value
        }
        result += DurationBucket.allCases.map { var value = baseSummary
            value.duration = $0
            return value
        }
        result += SmallBucket.allCases.map { var value = baseSummary
            value.played = $0
            return value
        }
        result += SmallBucket.allCases.map { var value = baseSummary
            value.skipped = $0
            return value
        }
        result += ShowEndReason.allCases.map { var value = baseSummary
            value.endedBy = $0
            return value
        }
        for flag in [true, false] {
            var value = baseSummary
            value.requestsUsed = flag
            value.autoScrollUsed = flag
            value.reordered = flag
            result.append(value)
        }
        return result
    }
}

/// Phase 3 AI rows (R74, R98): every enum value and bucket at least once.
enum AISample {
    static var all: [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        let providers = AIProviderUsed.allCases
        let rows = [
            PasteSource.allCases.count, PasteFallback.allCases.count,
            LatencyBucket.allCases.count, PasteOutcome.allCases.count,
            CorrectionBucket.allCases.count, providers.count,
        ].max() ?? 0
        for row in 0 ..< rows {
            events.append(.aiPasteFinished(PasteFinishedSummary(
                source: pick(PasteSource.allCases, row),
                provider: pick(providers, row),
                fallback: pick(PasteFallback.allCases, row),
                latency: pick(LatencyBucket.allCases, row),
                outcome: pick(PasteOutcome.allCases, row),
                correction: pick(CorrectionBucket.allCases, row),
                romanHindi: row.isMultiple(of: 2),
            )))
        }
        let downloads = max(
            ModelDownloadResult.allCases.count,
            DownloadDurationBucket.allCases.count,
        )
        for row in 0 ..< downloads {
            events.append(.aiModelDownload(ModelDownloadSummary(
                result: pick(ModelDownloadResult.allCases, row),
                kind: pick(ModelDownloadKind.allCases, row),
                duration: pick(DownloadDurationBucket.allCases, row),
                ramUnder16: row.isMultiple(of: 2),
            )))
        }
        let buckets = SmallBucket.allCases
        for row in buckets.indices {
            events.append(.aiAssistantUsed(AssistantUsedSummary(
                context: pick(AssistantContext.allCases, row),
                lexiconChips: buckets[row],
                suggestedShown: pick(buckets, row + 1),
                suggestedAccepted: pick(buckets, row + 2),
                provider: pick(providers, row),
                rebuilt: row.isMultiple(of: 2),
                artistChips: row.isMultiple(of: 3),
                albumChips: !row.isMultiple(of: 3),
            )))
        }
        for action in SmartFilterAction.allCases {
            events += buckets.map { .aiSmartFilterUsed(action: action, conditions: $0) }
        }
        return events
    }

    private static func pick<T>(_ values: [T], _ row: Int) -> T {
        values[row % values.count]
    }
}

extension VocabularySample {
    /// Row 31 (P9-1): every value of every closed enum at least once.
    static var pdfExportEvents: [AnalyticsEvent] {
        let targets = PDFExportTarget.allCases, parts = PDFExportPart.allCases
        let papers = PDFExportPaper.allCases, sizes = PDFExportSize.allCases
        let columns = PDFExportColumns.allCases, repeats = PDFExportRepeats.allCases
        let diagrams = PDFExportDiagrams.allCases, fills = PDFExportFills.allCases
        let times = RenderTimeBucket.allCases
        let rows = [
            targets.count, parts.count, papers.count, sizes.count, columns.count,
            repeats.count, diagrams.count, fills.count, times.count,
        ].max() ?? 0
        return (0 ..< rows).map { row in
            .pdfExported(PDFExportSummary(
                target: targets[row % targets.count],
                part: parts[row % parts.count],
                paper: papers[row % papers.count],
                size: sizes[row % sizes.count],
                columns: columns[row % columns.count],
                repeats: repeats[row % repeats.count],
                fitOnePage: row.isMultiple(of: 2),
                sectionMap: !row.isMultiple(of: 2),
                stageNotes: row.isMultiple(of: 3),
                diagrams: diagrams[row % diagrams.count],
                fills: fills[row % fills.count],
                saved: row.isMultiple(of: 2),
                printed: row.isMultiple(of: 3),
                shared: row.isMultiple(of: 4),
                songs: SmallBucket(row + 1),
                pages: SmallBucket(row * 3),
                medleys: SmallBucket(0),
                optionChanges: SmallBucket(row),
                renderTime: times[row % times.count],
            ))
        }
    }
}
