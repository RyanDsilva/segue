import Foundation
import Library
@testable import SegueUI
import Services
import Setlists
import Support
import Testing

/// The set composer on a real app session (P8-5 section 13.4): each Return is one store
/// write and one undo step; "in A" travels with the song; "---" is a break; a song already
/// in the set, a line that names nothing and a read-only setlist write nothing; the
/// matcher follows the catalog; analytics carry only closed-vocabulary values.
@MainActor
struct SetComposerViewModelTests {
    private static let fridayID = "01JC0000000000000000000F01"
    private static let songs = [
        ("kesariya", "{title: Kesariya}\n{key: G}\n{duration: 4:28}\n[G]Mujhko itna bataaye koi\n"),
        (
            "tum-hi-ho",
            "{title: Tum Hi Ho}\n{artist: Arijit Singh}\n{key: Bb}\n[Bb]Hum tere bin\n",
        ),
        ("no-key", "{title: Naina}\nNaina lade\n"),
    ]

    private static func id(_ index: Int) -> SongID {
        SongID(ULID(
            string: "01JC0000000000000000000A0\(index)",
        )!) // swiftlint:disable:this force_unwrapping
    }

    private struct Fixture {
        var env: TestEnvironment
        var session: LibrarySession
        var manager: UndoManager
        var friday: SetlistID
        var recording: RecordingLog
    }

    private static func open(readOnly: Bool = false) async throws -> Fixture {
        let env = try TestEnvironment()
        for folder in ["songs", "setlists"] {
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
        }
        for (index, song) in songs.enumerated() {
            try env.write(song.1, to: "songs/\(song.0).cho")
            try env.write(
                #"{"schemaVersion": 3, "id": "\#(id(index))", "#
                    + #""createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-01T10:00:00Z"}"#,
                to: "songs/\(song.0).segue.json",
            )
        }
        let version = readOnly ? 99 : 3
        try env.write(
            #"{"schemaVersion": \#(version), "id": "\#(fridayID)", "#
                + #""name": "Friday", "entries": []}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        session.setlists.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        let friday = try SetlistID(#require(ULID(string: fridayID)))
        return Fixture(
            env: env,
            session: session,
            manager: manager,
            friday: friday,
            recording: recording,
        )
    }

    /// Types `line` and presses Return, as one undo group.
    @discardableResult
    private func compose(_ fix: Fixture, _ line: String, choice: Int = 0) async -> ComposeOutcome {
        let composer = fix.session.setlists.composer
        composer.setText(line, library: fix.session.library)
        fix.manager.beginUndoGrouping()
        let outcome = await fix.session.setlists.compose(
            composer.resolution,
            choice: choice,
            in: fix.friday,
            songs: fix.session.library.song(id:),
            entry: .shortcut,
        )
        fix.manager.endUndoGrouping()
        composer.noteReturn(outcome)
        return outcome
    }

    private func entries(_ fix: Fixture) -> [SetlistEntry] {
        fix.session.setlists.setlist(fix.friday)?.entries ?? []
    }

    @Test
    func `return appends the match as one undo step and undo removes it`() async throws {
        let fix = try await Self.open()
        let outcome = await compose(fix, "kesar")
        guard case .added = outcome else {
            Issue.record("expected an add, got \(outcome)")
            return
        }
        #expect(entries(fix).map(\.songId) == [Self.id(0)])
        #expect(entries(fix).first?.overrides == SetlistOverrides())
        #expect(fix.manager.undoActionName == "Add Song")
        fix.manager.undo()
        try await fix.env.waitFor { entries(fix).isEmpty ? true : nil }
    }

    @Test
    func `a key token travels with the song and one undo removes both`() async throws {
        let fix = try await Self.open()
        await compose(fix, "kesariyaa in A")
        // Kesariya is in G with no capo: "in A" is +2.
        #expect(entries(fix).first?.overrides == SetlistOverrides(transpose: 2))
        #expect(fix.manager.undoActionName == "Add Song")
        fix.manager.undo()
        try await fix.env.waitFor { entries(fix).isEmpty ? true : nil }
        #expect(!fix.manager.canUndo)
    }

    @Test
    func `a key on a song with no key is ignored and the song added plain`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        composer.setText("naina in A", library: fix.session.library)
        let state = try ComposerRowState(
            composer: composer,
            setlist: #require(fix.session.setlists.setlist(fix.friday)),
            library: fix.session.library,
        )
        #expect(state.status == .note("This song has no key, so 'in A' is ignored"))
        await compose(fix, "naina in A")
        #expect(entries(fix).map(\.songId) == [Self.id(2)])
        #expect(entries(fix).first?.overrides == SetlistOverrides())
    }

    /// P8-8 section 3.5.1: trailing artist words qualify the title, a line naming only an
    /// artist lists their songs; both say "By ..." and row 24 says which.
    @Test
    func `an artist qualifies a title or names the songs, and the status says by whom`()
        async throws
    {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        for line in ["tum hi ho arijit", "arijit"] {
            composer.setText(line, library: fix.session.library)
            let state = try ComposerRowState(
                composer: composer,
                setlist: #require(fix.session.setlists.setlist(fix.friday)),
                library: fix.session.library,
            )
            #expect(composer.chosen?.id == Self.id(1), "\(line)")
            #expect(state.status == .note("By Arijit Singh"), "\(line)")
        }
        await compose(fix, "tum hi ho arijit")
        let composed = fix.recording.entries()
            .filter { $0["name"] as? String == "Segue.Setlist.composed" }
            .compactMap { $0["params"] as? [String: String] }
        #expect(composed.last?["segue.artistWords"] == "true")
        #expect(composed.last?["segue.tier"] == "exactTitle")
    }

    @Test
    func `three dashes append a labelled break as one undo step`() async throws {
        let fix = try await Self.open()
        await compose(fix, "kesariya")
        let outcome = await compose(fix, "---")
        guard case .breakAdded = outcome else {
            Issue.record("expected a break, got \(outcome)")
            return
        }
        #expect(entries(fix).last?.breakInfo == SetlistBreak(label: "Set 2"))
        #expect(fix.manager.undoActionName == "Insert Break")
    }

    @Test
    func `a song already in the set, no match and a read-only setlist write nothing`(
    ) async throws {
        let fix = try await Self.open()
        await compose(fix, "kesariya")
        let first = try #require(entries(fix).first)
        let before = try fix.env.read("setlists/friday.setlist.json")

        #expect(await compose(fix, "Kesariyaa") == .alreadyInSet(first.itemId))
        #expect(await compose(fix, "qqqq") == .noMatch)
        #expect(await compose(fix, "   ") == .ignored)
        #expect(entries(fix).count == 1)
        #expect(try fix.env.read("setlists/friday.setlist.json") == before)

        let readOnly = try await Self.open(readOnly: true)
        #expect(await compose(readOnly, "kesariya") == .ignored)
        #expect(entries(readOnly).isEmpty)
    }

    @Test
    func `the matcher follows the catalog`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        composer.setText("channa", library: fix.session.library)
        #expect(composer.resolution.matches.isEmpty)

        _ = try await fix.session.library.store
            .createSong(source: "{title: Channa Mereya}\n[Em]Achha chalta hoon\n")
        await fix.session.library.reload()
        composer.refresh(library: fix.session.library)
        let match = try #require(composer.chosen)
        #expect(fix.session.library.song(id: match.id).map(SongSummary.title) == "Channa Mereya")
    }

    @Test
    func `alternatives cycle and wrap, escape closes then clears then leaves`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        composer.setText("t", library: fix.session.library)
        // "t" is only a prefix of Tum: one candidate, nothing to cycle.
        #expect(!composer.cycle(by: 1))
        composer.setText("a", library: fix.session.library)
        #expect(composer.resolution.matches.isEmpty)

        let library = fix.session.library
        _ = try await library.store.createSong(source: "{title: Tum Hi Ho Bandhu}\nHo bandhu\n")
        await library.reload()
        composer.setText("tum hi", library: library)
        #expect(composer.resolution.matches.count == 2)
        #expect(composer.cycle(by: 1))
        #expect(composer.choice == 1)
        #expect(composer.showsAlternatives)
        #expect(composer.cycle(by: 1))
        #expect(composer.choice == 0)
        #expect(composer.cycle(by: -1))
        #expect(composer.choice == 1)
        // Typing resets the cycle to the new best match.
        composer.setText("tum hi h", library: library)
        #expect(composer.choice == 0)
        #expect(!composer.showsAlternatives)

        #expect(composer.cycle(by: 1))
        #expect(composer.escape() == .closedAlternatives)
        #expect(composer.escape() == .cleared)
        #expect(composer.text.isEmpty)
        #expect(composer.escape() == .leave)
    }

    @Test
    func `composed signals carry only closed-vocabulary values`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        _ = composer.focusChanged(true)
        await compose(fix, "kesriya in A")
        await compose(fix, "---")
        await compose(fix, "kesariya")
        await compose(fix, "qqqq")
        let session = try #require(composer.focusChanged(false))
        fix.session.setlists.recordComposerSession(songs: session.songs, cycles: session.cycles)

        let signals = fix.recording.entries().filter { $0["kind"] as? String == "signal" }
        let composed = signals.filter { $0["name"] as? String == "Segue.Setlist.composed" }
            .compactMap { $0["params"] as? [String: String] }
        #expect(composed.map { $0["segue.action"] } == ["song", "break", "alreadyInSet", "noMatch"])
        #expect(composed.first == [
            "segue.action": "song", "segue.tier": "fuzzyTitle", "segue.form": "normalized",
            "segue.alternative": "false", "segue.key": "true", "segue.entry": "shortcut",
            "segue.artistWords": "false",
        ])
        let vocabulary: [String: Set<String>] = [
            "segue.action": Set(ComposerAction.allCases.map(\.rawValue)),
            "segue.tier": Set(ComposerTier.allCases.map(\.rawValue)),
            "segue.form": Set(ComposerForm.allCases.map(\.rawValue)),
            "segue.alternative": ["true", "false"],
            "segue.key": ["true", "false"],
            "segue.entry": Set(ComposerEntry.allCases.map(\.rawValue)),
            "segue.artistWords": ["true", "false"],
        ]
        for params in composed {
            #expect(Set(params.keys) == Set(vocabulary.keys))
            for (key, value) in params {
                #expect(vocabulary[key]?.contains(value) == true, "\(key)=\(value)")
            }
        }
        let sessions = signals.filter { $0["name"] as? String == "Segue.Setlist.composerSession" }
        #expect(sessions.compactMap { $0["params"] as? [String: String] } == [
            ["segue.songs": "1", "segue.cycles": "0"],
        ])
    }
}
