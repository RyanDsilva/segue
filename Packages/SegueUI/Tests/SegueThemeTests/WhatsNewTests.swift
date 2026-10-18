import Foundation
@testable import SegueUI
import Testing

/// What's New (WS2b 4.3): the app-side reading of WS4's generated `website/changelog.json`
/// (schema 1), version comparison, which releases a launch shows, and the Help item's range.
@MainActor
struct WhatsNewTests {
    private static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    // MARK: The bundled file

    @Test
    func `the generated changelog follows the app side schema 1 rules`() throws {
        let data = try Data(contentsOf: Self.repo.appending(path: "website/changelog.json"))
        let changelog = try #require(Changelog.decode(data))
        #expect(changelog.schema == 1)
        let versions = changelog.releases.compactMap(\.appVersion)
        #expect(versions.count == changelog.releases.count, "every version parses")
        #expect(Set(versions).count == versions.count, "versions are unique")
        #expect(versions == versions.sorted(by: >), "newest first")
        for release in changelog.releases {
            #expect(release.draft != true, "drafts never reach the generated file")
            #expect((1 ... 60).contains(release.title.count), "\(release.title)")
            #expect((release.summary?.count ?? 0) <= 200)
            #expect((1 ... 8).contains(release.highlights.count))
            for item in release.highlights {
                #expect((1 ... 120).contains(item.text.count), "\(item.text)")
                #expect(!item.text.contains("\u{2014}"), "no em dashes")
                if let help = item.help {
                    #expect(help.hasPrefix("/"), "help is site-relative: \(help)")
                }
            }
        }
    }

    /// The release check (WS5 sets SEGUE_RELEASE_CHECK=1): the bundled file has a published
    /// entry for MARKETING_VERSION. Skipped otherwise, while the 0.5 entry is still a draft.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SEGUE_RELEASE_CHECK"] == "1"))
    func `running version has entry`() throws {
        let config = try String(
            contentsOf: Self.repo.appending(path: "Config/Version.xcconfig"),
            encoding: .utf8,
        )
        let line = config.split(separator: "\n").first { $0.hasPrefix("MARKETING_VERSION") }
        let version = String(line?.split(separator: "=").last ?? "")
            .trimmingCharacters(in: .whitespaces)
        let data = try Data(contentsOf: Self.repo.appending(path: "website/changelog.json"))
        let changelog = try #require(Changelog.decode(data))
        #expect(changelog.published.contains { $0.appVersion == AppVersion(version) })
    }

    /// A version literal the test knows is valid.
    private static func version(_ text: String) -> AppVersion {
        guard let version = AppVersion(text) else { preconditionFailure("bad version \(text)") }
        return version
    }

    // MARK: Versions

    @Test(arguments: [
        ("0.5", "0.5.0", 0), ("0.10", "0.9.1", 1), ("0.5", "0.6", -1), ("1", "0.99", 1),
        ("0.5.1", "0.5", 1), ("2.0.0", "2", 0),
    ])
    func `versions compare numerically per component`(
        _ lhs: String,
        _ rhs: String,
        _ order: Int,
    ) throws {
        let left = try #require(AppVersion(lhs))
        let right = try #require(AppVersion(rhs))
        #expect((left < right ? -1 : left == right ? 0 : 1) == order)
    }

    @Test(arguments: ["", "0.x", "1..2", "-1", "v1"])
    func `malformed versions do not parse`(_ text: String) {
        #expect(AppVersion(text) == nil)
    }

    // MARK: Launch decisions

    private static func release(
        _ version: String,
        show: Bool,
        kinds: [Changelog.Highlight.Kind] = [.new],
        draft: Bool? = nil,
    ) -> Changelog.Release {
        Changelog.Release(
            version: version,
            date: "2027-01-15",
            title: "Release \(version)",
            summary: nil,
            showInApp: show,
            draft: draft,
            highlights: kinds.enumerated().map { index, kind in
                Changelog.Highlight(kind: kind, text: "Change \(index) in \(version).", help: nil)
            },
        )
    }

    private static let log = Changelog(releases: [
        release("0.7", show: true, kinds: [.new, .new, .improved]),
        release("0.6.1", show: false, kinds: [.fixed]),
        release("0.6", show: true),
        release("0.5", show: false),
    ])

    private func decide(_ lastSeen: String?, _ current: String, _ log: Changelog? = log)
        -> WhatsNewPolicy.LaunchDecision
    {
        WhatsNewPolicy.atLaunch(
            changelog: log,
            lastSeen: lastSeen.flatMap(AppVersion.init),
            current: Self.version(current),
        )
    }

    @Test
    func `a release in range with show in app shows only those releases`() {
        guard case let .show(content) = decide("0.6", "0.7") else {
            Issue.record("no sheet")
            return
        }
        #expect(content.title == "What's New in Segue 0.7")
        #expect(content.releases.map(\.version) == ["0.7"], "0.6.1 is not shown")
        #expect(content.releases[0].highlights.map(\.kind) == [.new, .new, .improved])
    }

    @Test
    func `the silent and empty cases`() {
        // Only showInApp false in range: credited silently.
        #expect(decide("0.6", "0.6.1") == .creditSilently)
        // Already seen, a downgrade, a version with no entry, no file: nothing.
        #expect(decide("0.7", "0.7") == .nothing)
        #expect(decide("0.7", "0.6") == .nothing)
        #expect(decide("0.6", "0.8") == .nothing)
        #expect(decide("0.6", "0.7", nil) == .nothing)
        #expect(decide(nil, "0.7", Changelog(releases: [])) == .nothing)
        // Drafts never count.
        let drafted = Changelog(releases: [Self.release("0.8", show: true, draft: true)])
        #expect(decide("0.7", "0.8", drafted) == .nothing)
    }

    @Test
    func `an upgrader is credited with the release before this one`() {
        guard case let .show(content) = decide(nil, "0.7") else {
            Issue.record("an upgrader to 0.7 should see its notes")
            return
        }
        #expect(content.releases.map(\.version) == ["0.7"])
    }

    @Test
    func `at most eight rows with the overflow counted`() {
        let big = Changelog(releases: [
            Self.release("0.9", show: true, kinds: Array(repeating: .new, count: 6)),
            Self.release("0.8", show: true, kinds: Array(repeating: .fixed, count: 5)),
        ])
        guard case let .show(content) = decide("0.7", "0.9", big) else {
            Issue.record("no sheet")
            return
        }
        #expect(content.releases.flatMap(\.highlights).count == 8)
        #expect(content.overflow == 3)
    }

    @Test
    func `help shows this version and the two before whatever show in app says`() throws {
        let content = try #require(WhatsNewPolicy.forHelp(
            changelog: Self.log,
            current: Self.version("0.6.1"),
        ))
        #expect(content.releases.map(\.version) == ["0.6.1", "0.6", "0.5"])
        let newest = try #require(WhatsNewPolicy.forHelp(
            changelog: Self.log,
            current: Self.version("0.9"),
        ))
        #expect(newest.releases.map(\.version) == ["0.7", "0.6.1", "0.6"])
        #expect(WhatsNewPolicy.forHelp(
            changelog: Changelog(releases: []),
            current: Self.version("0.5"),
        ) == nil)
    }

    // MARK: Decoding

    @Test
    func `unknown keys are ignored and unknown schemas are refused`() throws {
        let json = """
        {"schema": 1, "future": true, "releases": [{"version": "0.6", "date": "2027-01-15",
         "title": "T", "showInApp": true, "extra": 3,
         "highlights": [{"kind": "new", "text": "A thing.", "help": "/help/live", "x": 1}]}]}
        """
        let log = try #require(Changelog.decode(Data(json.utf8)))
        let item = try #require(log.releases.first?.highlights.first)
        #expect(item.helpURL == SegueLinks.site.appending(path: "help/live"))
        #expect(log.releases.first?.displayDate == "January 15, 2027")
        #expect(Changelog.decode(Data(#"{"schema": 2, "releases": []}"#.utf8)) == nil)
        #expect(Changelog.decode(Data("not json".utf8)) == nil)
    }
}
