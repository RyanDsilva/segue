import Editing
import Foundation
import Ingest
import Library
@testable import SegueUI
import Services
import Testing

/// The review sheet's artist split (P8-8 sections 3.6, 3.7, 8, 13.2): the line under a
/// split credit, Keep as one in one edit, the line ending at a hand edit, Swap needing one
/// artist, and row 29 at Accept.
@MainActor
struct PasteReviewArtistSplitTests {
    static let paste = """
    Pahadi Raat
    Artist: Zoya & The Village Band

    G               C
    Pahadon pe raat utri, chaand ne kaha ruk ja
    D               G
    Thandi hawa ne gaaya, ghar ki taraf mud ja
    """

    private struct Fixture {
        let env: TestEnvironment
        let library: LibraryViewModel
        let recording: RecordingLog
    }

    private func open() async throws -> Fixture {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        library.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        return Fixture(env: env, library: library, recording: recording)
    }

    private func artists(_ item: PasteReviewItem) -> [String] {
        SourceSnapshot(text: item.text).document.metadata.artists
    }

    @Test
    func `a split credit shows its line and Keep as one merges it in one edit`() async throws {
        let fix = try await open()
        let (env, library, recording) = (fix.env, fix.library, fix.recording)
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let item = try #require(library.pasteReview?.selected)
        #expect(artists(item) == ["Zoya", "The Village Band"])
        #expect(item.standingSplits.map(\.original) == ["Zoya & The Village Band"])
        #expect(!item.canSwapTitleAndArtist)
        #expect(item.swapHelp == "Swap works with one artist")

        let before = item.text
        try item.keepAsOne(#require(item.standingSplits.first))
        #expect(artists(item) == ["Zoya & The Village Band"])
        #expect(item.standingSplits.isEmpty)
        #expect(item.text == before.replacingOccurrences(
            of: "{artist: Zoya}\n{artist: The Village Band}",
            with: "{artist: Zoya & The Village Band}",
        ))
        #expect(item.canSwapTitleAndArtist)

        await library.pasteReview?.awaitRefinement()
        await library.acceptPasteReview()
        #expect(try env.read("songs/pahadi-raat.cho").contains("{artist: Zoya & The Village Band}"))
        let split = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.artistSplit"
        })
        #expect(split["params"] as? [String: String] == [
            "segue.source": "paste", "segue.parts": "2-4", "segue.separator": "ampersand",
            "segue.outcome": "merged",
        ])
    }

    @Test
    func `a hand edit of the split chips ends the line and records edited`() async throws {
        let fix = try await open()
        let (env, library, recording) = (fix.env, fix.library, fix.recording)
        defer { withExtendedLifetime(env) {} }
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let item = try #require(library.pasteReview?.selected)
        let host = SongCardHost.draft(
            source: .init(get: { item.text }, set: { item.edit($0) }),
            songID: .standIn(),
        )
        host.perform(SongCardWrite.artists(["Zoya", "Village Band"]))
        #expect(artists(item) == ["Zoya", "Village Band"])
        #expect(item.standingSplits.isEmpty)
        await library.pasteReview?.awaitRefinement()
        await library.acceptPasteReview()
        let split = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.artistSplit"
        })
        #expect((split["params"] as? [String: String])?["segue.outcome"] == "edited")
    }

    @Test
    func `a split kept as is records kept, and one artist leaves Swap on`() async throws {
        let fix = try await open()
        let (env, library, recording) = (fix.env, fix.library, fix.recording)
        defer { withExtendedLifetime(env) {} }
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        await library.pasteReview?.awaitRefinement()
        await library.acceptPasteReview()
        let split = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.artistSplit"
        })
        #expect((split["params"] as? [String: String])?["segue.outcome"] == "kept")

        library.beginPasteReview(text: PasteReviewTests.paste, source: .clipboard)
        let single = try #require(library.pasteReview?.selected)
        #expect(single.standingSplits.isEmpty && single.canSwapTitleAndArtist)
    }
}
