#if os(macOS)
    import Foundation
    import Observation
    import os

    // WS2b 4.3: What's New reads only the bundled, generated `website/changelog.json` (WS4's
    // schema 1). Never fetched (A16, I-3).

    /// A marketing version compared numerically per component, missing components as 0:
    /// `0.5` == `0.5.0`, `0.10` > `0.9.1`.
    public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
        public let components: [Int]
        public let description: String

        /// nil for a string that is not dot-separated non-negative integers.
        public init?(_ string: String) {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            let numbers = parts.compactMap { part in
                part.allSatisfy(\.isASCII) ? Int(part) : nil
            }
            guard !parts.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 })
            else { return nil }
            components = numbers
            description = trimmed
        }

        private func padded(to count: Int) -> [Int] {
            components + Array(repeating: 0, count: max(0, count - components.count))
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            return lhs.padded(to: count) == rhs.padded(to: count)
        }

        public func hash(into hasher: inout Hasher) {
            var trimmed = components
            while trimmed.last == 0 {
                trimmed.removeLast()
            }
            hasher.combine(trimmed)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            return lhs.padded(to: count).lexicographicallyPrecedes(rhs.padded(to: count))
        }
    }

    /// The app-side reading of WS4's changelog, schema 1. Unknown keys are ignored.
    public struct Changelog: Sendable, Equatable, Decodable {
        public static let supportedSchema = 1

        public var schema: Int
        /// Newest first.
        public var releases: [Release]

        public struct Release: Sendable, Equatable, Decodable, Identifiable {
            public var version: String
            /// `YYYY-MM-DD`.
            public var date: String
            public var title: String
            public var summary: String?
            /// The release author's choice: this release gets the automatic sheet.
            public var showInApp: Bool
            /// Never in the generated file; a release marked draft is skipped anyway.
            public var draft: Bool?
            public var highlights: [Highlight]

            public var id: String {
                version
            }

            public var appVersion: AppVersion? {
                AppVersion(version)
            }

            /// The date as the sheet shows it ("November 20, 2026"); the raw string if it
            /// does not parse.
            public var displayDate: String {
                guard let day = Self.dayFormat.date(from: date) else { return date }
                return Self.displayFormat.string(from: day)
            }

            /// Both in UTC, so the day never shifts with the Mac's time zone.
            private static let dayFormat: DateFormatter = {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            }()

            private static let displayFormat: DateFormatter = {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "MMMM d, yyyy"
                return formatter
            }()
        }

        public struct Highlight: Sendable, Equatable, Decodable {
            public enum Kind: String, Sendable, Decodable, CaseIterable {
                case new
                case improved
                case fixed

                /// The badge word (a word, never only a colour).
                public var label: String {
                    switch self {
                    case .new: "New"
                    case .improved: "Improved"
                    case .fixed: "Fixed"
                    }
                }
            }

            public var kind: Kind
            public var text: String
            /// A site-relative help path on the site, e.g. a guide page ("/guide/go-on-stage").
            public var help: String?

            /// `SegueLinks.site` + `help`, for "Learn More".
            public var helpURL: URL? {
                guard let help, help.hasPrefix("/") else { return nil }
                return URL(string: help, relativeTo: SegueLinks.site)?.absoluteURL
            }
        }

        public init(schema: Int = Self.supportedSchema, releases: [Release]) {
            self.schema = schema
            self.releases = releases
        }

        /// Releases that ship (drafts dropped).
        var published: [Release] {
            releases.filter { $0.draft != true && $0.appVersion != nil }
        }

        private struct SchemaProbe: Decodable {
            var schema: Int
        }

        /// Reads `data`; nil (one log line) for a schema major the app does not know or a
        /// file it cannot read. Never throws or crashes.
        public static func decode(_ data: Data) -> Self? {
            let decoder = JSONDecoder()
            guard let probe = try? decoder.decode(SchemaProbe.self, from: data) else {
                logger.error("changelog.json is unreadable; no What's New")
                return nil
            }
            guard probe.schema == supportedSchema else {
                logger.error("changelog.json schema \(probe.schema) is unknown; no What's New")
                return nil
            }
            do {
                return try decoder.decode(Self.self, from: data)
            } catch {
                logger.error("changelog.json does not decode; no What's New")
                return nil
            }
        }

        /// Reads the file at `url`; nil when it is missing or unreadable.
        public static func load(from url: URL?) -> Self? {
            guard let url else {
                logger.error("No bundled changelog.json; no What's New")
                return nil
            }
            guard let data = try? Data(contentsOf: url) else {
                logger.error("changelog.json is missing; no What's New")
                return nil
            }
            return decode(data)
        }

        private static let logger = Logger(subsystem: "dev.ryandsilva.segue", category: "whats-new")
    }

    /// What the sheet shows: a title, the releases, at most `maxRows` highlight rows in total
    /// and the number left out.
    public struct WhatsNewContent: Sendable, Equatable {
        public static let maxRows = 8

        public var version: String
        public var releases: [Changelog.Release]
        /// Highlights beyond `maxRows`, shown as "and N more changes".
        public var overflow: Int

        public var title: String {
            "What's New in Segue \(version)"
        }

        /// Trims `releases` (newest first) to `maxRows` highlight rows.
        init(version: String, releases: [Changelog.Release]) {
            self.version = version
            var budget = Self.maxRows
            var kept: [Changelog.Release] = []
            var dropped = 0
            for var release in releases {
                let take = min(budget, release.highlights.count)
                dropped += release.highlights.count - take
                budget -= take
                if take > 0 {
                    release.highlights = Array(release.highlights.prefix(take))
                    kept.append(release)
                }
            }
            self.releases = kept
            overflow = dropped
        }
    }

    /// When the What's New sheet appears (4.3). Pure, so `WhatsNewTests` covers it.
    public enum WhatsNewPolicy {
        public enum LaunchDecision: Equatable, Sendable {
            /// Show the sheet (dismissing it credits `current`).
            case show(WhatsNewContent)
            /// Nothing to show for this range: credit `current` without a sheet.
            case creditSilently
            /// No sheet, and `lastSeenVersion` stays as it is.
            case nothing
        }

        /// The launch decision for `current`, given the last version whose notes were seen
        /// (nil: an upgrader from a build without What's New).
        public static func atLaunch(
            changelog: Changelog?,
            lastSeen: AppVersion?,
            current: AppVersion,
        ) -> LaunchDecision {
            guard let changelog else { return .nothing }
            let releases = changelog.published
            // The running version has no entry (newer than every entry): no sheet.
            guard releases.contains(where: { $0.appVersion == current }) else { return .nothing }
            // An upgrader is credited with the newest release before this one, so this
            // release's notes show once.
            let floor = lastSeen ?? releases.compactMap(\.appVersion).filter { $0 < current }.max()
            if let floor, floor >= current {
                // Already seen, or a downgrade.
                return .nothing
            }
            let inRange = releases.filter { release in
                guard let version = release.appVersion else { return false }
                return version <= current && floor.map { version > $0 } ?? true
            }
            let shown = inRange.filter(\.showInApp)
            guard !shown.isEmpty else { return .creditSilently }
            return .show(WhatsNewContent(version: current.description, releases: shown))
        }

        /// Help > What's New in Segue: the running version's entry (or the newest when it has
        /// none) and the two releases before it, whatever their `showInApp`. nil when there is
        /// nothing to show (the Help item then opens the web changelog).
        public static func forHelp(changelog: Changelog?, current: AppVersion) -> WhatsNewContent? {
            guard let releases = changelog?.published, !releases.isEmpty else { return nil }
            let sorted = releases.sorted { lhs, rhs in
                (lhs.appVersion ?? current) > (rhs.appVersion ?? current)
            }
            let anchor = sorted.firstIndex { $0.appVersion == current } ?? 0
            let shown = Array(sorted[anchor...].prefix(3))
            return WhatsNewContent(version: shown[0].version, releases: shown)
        }
    }

    /// The last version whose notes the user saw (WS2b section 3, `whatsNew.lastSeenVersion`).
    @MainActor
    public final class WhatsNewStore {
        static let lastSeenKey = "whatsNew.lastSeenVersion"

        private let defaults: UserDefaults

        public init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        public var lastSeenVersion: String? {
            defaults.string(forKey: Self.lastSeenKey)
        }

        func markSeen(_ version: String) {
            defaults.set(version, forKey: Self.lastSeenKey)
        }
    }
#endif
