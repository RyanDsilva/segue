import Foundation
import Plugins
import Services

/// What a failure says and offers (spec 6.8, 8.7): never an alert, never a saved song. Pure,
/// so every case has a table test.
enum ImportCopy {
    /// An action a failure offers.
    enum Action: String, CaseIterable, Sendable {
        case tryAgain
        case openHere
        case openInBrowser
        case importSavedPage
        case pasteInstead
        case searchInBrowser

        var title: String {
            switch self {
            case .tryAgain: "Try Again"
            case .openHere: "Open Here"
            case .openInBrowser: "Open in Safari"
            case .importSavedPage: "Import a Saved Page…"
            case .pasteInstead: "Paste the Page Instead"
            case .searchInBrowser: "Search in Safari"
            }
        }
    }

    /// A failure as shown.
    struct Message: Equatable, Sendable {
        var text: String
        var actions: [Action]
        /// `busy` and `backingOff`: Import or Search stays off until then.
        var retryAt: Date?
    }

    /// The web field's message for a failed page read (spec 8.7). `host` is the page's host.
    static func page(_ failure: ImportFailure, host: String, now: Date) -> Message {
        switch failure {
        case .offline:
            Message(
                text: "You're offline. Importing a web page needs the internet.",
                actions: [.tryAgain],
            )
        case .server, .timedOut:
            Message(
                text: "\(host) isn't answering right now.",
                actions: [.tryAgain, .openInBrowser],
            )
        case .challenged:
            Message(
                text: "\(host) wants to check you're a person.",
                actions: [.openHere, .openInBrowser, .importSavedPage, .pasteInstead],
            )
        case .blocked:
            Message(
                text: "\(host) doesn't let apps read this page.",
                actions: [.openInBrowser, .importSavedPage, .pasteInstead],
            )
        case let .backingOff(retryAfter):
            backingOff(host, retryAfter: retryAfter, now: now, actions: [
                .openInBrowser, .pasteInstead,
            ])
        case .notFound:
            Message(text: "That page doesn't exist anymore.", actions: [.openInBrowser])
        case .notAPage, .tooLarge, .unsupportedScript:
            Message(text: "That address isn't a web page Segue can read.", actions: [])
        case let .noChart(reason):
            Message(text: noChart(reason), actions: [.openInBrowser, .pasteInstead])
        case let .busy(retryAfter):
            busy(host, retryAfter: retryAfter, now: now)
        case .cancelled:
            Message(text: "", actions: [])
        }
    }

    /// A search group's status line (spec 6.8): it names its source; the other groups are
    /// unaffected.
    static func search(_ failure: ImportFailure, source: String, now: Date) -> Message {
        switch failure {
        case .offline:
            Message(text: "You're offline. Search needs the internet.", actions: [.tryAgain])
        case .notAPage, .notFound, .server, .timedOut, .tooLarge, .unsupportedScript:
            Message(text: "\(source) isn't answering right now.", actions: [.tryAgain])
        case .challenged:
            Message(
                text: "\(source) wants to check you're a person.",
                actions: [.openHere, .searchInBrowser],
            )
        case .blocked:
            Message(
                text: "\(source) doesn't let apps search it right now.",
                actions: [.searchInBrowser],
            )
        case let .backingOff(retryAfter):
            backingOff(source, retryAfter: retryAfter, now: now, actions: [.searchInBrowser])
        case .noChart:
            Message(text: "No results.", actions: [])
        case let .busy(retryAfter):
            busy(source, retryAfter: retryAfter, now: now)
        case .cancelled:
            Message(text: "", actions: [])
        }
    }

    static func noChart(_ reason: NoChartReason) -> String {
        switch reason {
        case .notFound: "Segue couldn't find a chord chart on this page."
        case .tab: "This page is a tab, not a chord chart."
        case .pro: "Pro pages have no chord chart Segue can read."
        case .removed: "The site has removed this song."
        }
    }

    private static func busy(_ name: String, retryAfter: Duration?, now: Date) -> Message {
        let seconds = max(1, Int(((retryAfter ?? .seconds(5)) / .seconds(1)).rounded(.up)))
        return Message(
            text: "\(name) is busy. Try again in \(seconds) seconds.",
            actions: [],
            retryAt: now.addingTimeInterval(TimeInterval(seconds)),
        )
    }

    private static func backingOff(
        _ name: String,
        retryAfter: Duration,
        now: Date,
        actions: [Action],
    ) -> Message {
        let until = now.addingTimeInterval(retryAfter / .seconds(1))
        let time = until.formatted(date: .omitted, time: .shortened)
        return Message(
            text: "\(name) asked Segue to wait. Try again after \(time).",
            actions: actions,
            retryAt: until,
        )
    }

    // MARK: Analytics (spec 12)

    static func outcome(_ failure: ImportFailure) -> WebImportOutcome {
        switch failure {
        case .noChart, .unsupportedScript: .noChart
        case .blocked: .blocked
        case .challenged: .challenged
        case .backingOff: .backingOff
        case .notFound: .notFound
        case .offline: .offline
        case .busy: .busy
        case .cancelled: .cancelled
        case .notAPage, .server, .timedOut, .tooLarge: .failed
        }
    }

    static func reader(_ kind: ReaderKind) -> ImportReader {
        switch kind {
        case .tabJSON: .tabJSON
        case .chordPre: .chordPre
        case .chordSpans: .chordSpans
        case .genericPage: .genericPage
        case .lyricsRecord: .lyricsRecord
        }
    }

    static func loadPath(_ path: LoadPath) -> ImportLoadPath {
        switch path {
        case .plain: .plain
        case .webKit: .webKit
        case .savedFile: .savedFile
        }
    }

    static func challenge(_ kind: ChallengeKind) -> ImportChallenge {
        switch kind {
        case .notChallenged: .noChallenge
        case .nonInteractive: .nonInteractive
        case .managed: .managed
        case .interactive: .interactive
        case .unknown: .unknown
        }
    }

    static func group(_ group: SearchGroup) -> ImportSearchGroup {
        switch group {
        case .tabJSON: .tabJSON
        case .chordPre: .chordPre
        case .lyricsRecord: .lyricsRecord
        }
    }

    static func latency(since start: ContinuousClock.Instant) -> LatencyBucket {
        LatencyBucket(seconds: (ContinuousClock.now - start) / .seconds(1))
    }
}
