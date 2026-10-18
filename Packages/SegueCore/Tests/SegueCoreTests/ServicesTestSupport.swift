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
        events += SongSource.allCases.map(AnalyticsEvent.songCreated)
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
        events += HelpItem.allCases.map(AnalyticsEvent.helpOpened)
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
