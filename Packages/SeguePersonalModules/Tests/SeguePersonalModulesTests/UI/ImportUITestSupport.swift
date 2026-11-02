import Foundation
import ModelPort
import Plugins
@testable import SeguePersonalModules
@testable import SegueUI
import Services
import Synchronization

/// A search source that answers from a script (spec 15.3: the plugin views over stand-ins).
struct StubSearchSource: SongSearchSource {
    let id: String
    let displayName: String
    let group: SearchGroup
    var result: Result<[SearchCandidate], ImportFailure>
    var song: Result<ImportedSong, ImportFailure> = .failure(.notFound)
    var delay: Duration = .zero

    /// A lyrics source still answering after 30 s (a running search).
    static let slowLyrics = Self(
        id: "lyrics",
        displayName: "LRCLIB",
        group: .lyricsRecord,
        result: .success([]),
        delay: .seconds(30),
    )

    func search(_: SongQuery) async throws(ImportFailure) -> [SearchCandidate] {
        if delay > .zero {
            do {
                try await Task.sleep(for: delay)
            } catch {
                throw .cancelled
            }
        }
        return try result.get()
    }

    func song(for _: SearchCandidate) async throws(ImportFailure) -> ImportedSong {
        try song.get()
    }
}

/// The review sheet a plugin view hands its song to, and the events it records.
@MainActor
final class StubHost {
    let review: PasteReviewModel
    private(set) var events: [AnalyticsEvent] = []
    private(set) var opened: [URL] = []
    private(set) var cancelled = false

    init(search: Bool = false) {
        review = PasteReviewModel(
            items: [],
            router: Router(providers: []),
            services: .disabled,
            search: search,
            webImport: true,
        ) { _ in nil }
    }

    var host: ImportHost {
        ImportHost(
            review: review,
            router: Router(providers: []),
            nearDuplicates: nil,
            record: { [weak self] in self?.events.append($0) },
            open: { [weak self] in self?.opened.append($0) },
            cancel: { [weak self] in self?.cancelled = true },
        )
    }
}

enum ImportSamples {
    static let chart = """
    [Verse 1]
    Em                C
    Lanterns on the water tonight
    D                 Bm     C
    Every boat is coming home
    Em                C
    Gulls above the breakwater
    D                 Bm     C
    Every window burning bright

    [Chorus]
    C        D       Em
    Hold the light, hold the light
    C        D       G
    Bring her home tonight
    """

    static let lyrics = """
    Saans ki dor pe chalte rahe
    Khwaab ke ghar mein dhalte rahe

    Hold the light, hold the light
    Bring her home tonight
    """

    static func version(_ id: Int, _ version: Int, rating: Double, votes: Int) -> SearchCandidate {
        SearchCandidate(
            id: String(id),
            title: "Tum Hi Ho",
            artist: "Arijit Singh",
            album: "Aashiqui 2",
            kind: .chords,
            version: version,
            rating: rating,
            votes: votes,
            pageURL: web("https://tabs.ultimate-guitar.com/tab/x/tum-hi-ho-chords-\(id)"),
            songKey: "555",
        )
    }

    static let tabVersions = [
        version(1, 2, rating: 4.8, votes: 833),
        version(2, 3, rating: 4.8, votes: 50),
        version(3, 1, rating: 4.7, votes: 39),
        version(4, 4, rating: 4.8, votes: 14),
        SearchCandidate(
            id: "9",
            title: "Tum Hi Ho - Rehnuma",
            artist: "Shreya Ghoshal",
            kind: .chords,
            version: 1,
            rating: 4.6,
            votes: 23,
            pageURL: web("https://tabs.ultimate-guitar.com/tab/x/rehnuma-chords-9"),
            songKey: "556",
        ),
    ]

    static let lyricsRecord = SearchCandidate(
        id: "101",
        title: "Tum Hi Ho",
        artist: "Arijit Singh",
        album: "Aashiqui 2",
        kind: .lyrics,
        firstLines: "Saans ki dor pe chalte rahe\nKhwaab ke ghar mein dhalte rahe",
        lyrics: lyrics,
        romanized: true,
    )

    static let tabSong = ImportedSong(
        text: chart,
        fields: SourceFields(
            title: "Tum Hi Ho",
            artistCredit: "Arijit Singh",
            album: "Aashiqui 2",
            key: "Em",
            capo: 1,
        ),
        provenance: Provenance(
            sourceURL: web("https://tabs.ultimate-guitar.com/tab/x/tum-hi-ho-chords-1"),
            reader: .tabJSON,
            attribution: "From Ultimate Guitar · ver 2 · ★4.8",
        ),
    )

    @MainActor
    static func sources(
        tab: Result<[SearchCandidate], ImportFailure> = .success(tabVersions),
        pre: Result<[SearchCandidate], ImportFailure> = .failure(.challenged),
        lyrics: Result<[SearchCandidate], ImportFailure> = .success([lyricsRecord]),
    ) -> [any SongSearchSource] {
        [
            StubSearchSource(
                id: "tab",
                displayName: "Ultimate Guitar",
                group: .tabJSON,
                result: tab,
                song: .success(tabSong),
            ),
            StubSearchSource(id: "pre", displayName: "E-Chords", group: .chordPre, result: pre),
            StubSearchSource(
                id: "lyrics",
                displayName: "LRCLIB",
                group: .lyricsRecord,
                result: lyrics,
            ),
        ]
    }
}

extension FindLyricsModel {
    /// Waits for every group to answer (tests; no wall-clock polling of a status).
    func settle() async {
        for _ in 0 ..< 200 where isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func settlePreview() async {
        for _ in 0 ..< 200 {
            if case .loading = preview {
                try? await Task.sleep(for: .milliseconds(5))
            } else {
                return
            }
        }
    }
}
