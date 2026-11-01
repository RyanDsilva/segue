import AppKit
import Foundation
import Library
@testable import SegueUI
import Services
import Setlists
import Support
import SwiftUI
import Testing

/// The set composer's " + " medley on a real app session (P9-3 section 10): one Return is
/// one store write and one undo step "Add Medley"; a part that names nothing, a song twice
/// or a song already a medley member writes nothing and the status line says why; a part
/// that is a plain slot elsewhere joins as its reprise; the typed text is never rewritten.
/// The composer typing a medley is rendered light and dark to `.build/screenshots/p9-3/`.
@MainActor
struct SetComposerMedleyTests {
    private static let fridayID = "01JC0000000000000000000F01"
    private static let songs = [
        ("kesariya", "{title: Kesariya}\n{key: G}\n{tempo: 96}\n[G]Mujhko [C]itna [D]bataaye\n"),
        ("tum-hi-ho", "{title: Tum Hi Ho}\n{key: A}\n{tempo: 94}\n[A]Hum tere [E]bin\n"),
        ("channa", "{title: Channa Mereya}\n{key: D}\n{tempo: 100}\n[D]Achha [A]chalta\n"),
        ("harbour", "{title: Harbour Lights}\n{key: G}\n{tempo: 120}\n[G]Lights [D]low\n"),
        ("tum-se-hi", "{title: Tum Se Hi}\n{key: E}\n{tempo: 90}\n[E]Na hai [A]yeh\n"),
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

    /// "Friday" holds Harbour Lights as slot 1.
    private static func open() async throws -> Fixture {
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
        let slot = "01JC0000000000000000000E01"
        try env.write(
            #"{"schemaVersion": 7, "id": "\#(fridayID)", "name": "Friday", "#
                + #""entries": [{"itemId": "\#(slot)", "songId": "\#(id(3))"}]}"#,
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

    @discardableResult
    private func compose(_ fix: Fixture, _ line: String) async -> ComposeOutcome {
        let composer = fix.session.setlists.composer
        composer.setText(line, library: fix.session.library)
        fix.manager.beginUndoGrouping()
        let outcome = await fix.session.setlists.compose(
            composer.resolution,
            choice: composer.choice,
            partChoices: composer.partChoices,
            in: fix.friday,
            songs: fix.session.library.song(id:),
        )
        fix.manager.endUndoGrouping()
        return outcome
    }

    private func entries(_ fix: Fixture) -> [SetlistEntry] {
        fix.session.setlists.setlist(fix.friday)?.entries ?? []
    }

    @Test
    func `a plus line appends one medley as one undo step, keys per part`() async throws {
        let fix = try await Self.open()
        let outcome = await compose(fix, "kesariya in A + tum hi ho + harbour")
        guard case let .added(item) = outcome else {
            Issue.record("expected an add, got \(outcome)")
            return
        }
        #expect(entries(fix).count == 2)
        let medley = try #require(entries(fix).last?.medley)
        #expect(entries(fix).last?.itemId == item)
        #expect(medley.songIds == [Self.id(0), Self.id(1), Self.id(3)])
        // Kesariya is in G: "in A" is +2; the others keep their own key.
        #expect(medley.members.map(\.overrides.transpose) == [2, nil, nil])
        #expect(fix.manager.undoActionName == "Add Medley")
        // Harbour Lights is slot 1 and also a member: the reprise.
        #expect(fix.session.setlists.setlist(fix.friday)?.repeatedEntries.isEmpty == true)
        let json = try String(
            contentsOf: fix.env.libraryURL.appending(path: "setlists/friday.setlist.json"),
            encoding: .utf8,
        )
        #expect(json.contains("\"medley\" : {"))
        fix.manager.undo()
        try await fix.env.waitFor { entries(fix).count == 1 ? true : nil }

        let signals = fix.recording.entries().filter { $0["kind"] as? String == "signal" }
        let composed = signals.filter { $0["name"] as? String == "Segue.Setlist.composed" }
            .compactMap { $0["params"] as? [String: String] }
        #expect(composed.first?["segue.action"] == "medley")
        #expect(composed.first?["segue.members"] == "2-4")
        let medleys = signals.filter { $0["name"] as? String == "Segue.Setlist.medley" }
            .compactMap { $0["params"] as? [String: String] }
        #expect(medleys == [
            ["segue.action": "created", "segue.members": "2-4", "segue.entry": "composer"],
        ])
    }

    @Test
    func `a failing part writes nothing and the status line names it`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        let library = fix.session.library
        let setlist = try #require(fix.session.setlists.setlist(fix.friday))

        composer.setText("kesariya + tum hi ho + chana zzq", library: library)
        var state = ComposerRowState(composer: composer, setlist: setlist, library: library)
        #expect(state.status == .note("No song matches 'chana zzq' (song 3)"))
        #expect(await compose(fix, "kesariya + tum hi ho + chana zzq") == .noMatch)

        composer.setText("kesariya + tum hi ho + kesariya", library: library)
        state = ComposerRowState(composer: composer, setlist: setlist, library: library)
        #expect(state.status == .note("Kesariya is in this medley twice (songs 1 and 3)"))
        #expect(await compose(fix, "kesariya + tum hi ho + kesariya") == .noMatch)
        #expect(entries(fix).count == 1)

        // Once Tum Hi Ho is a member, a second medley holding it is refused.
        await compose(fix, "kesariya + tum hi ho")
        let current = try #require(fix.session.setlists.setlist(fix.friday))
        let medley = try #require(current.entries.last)
        composer.setText("channa + tum hi ho", library: library)
        state = ComposerRowState(composer: composer, setlist: current, library: library)
        #expect(state.status == .blocked(medley.itemId, "Tum Hi Ho is already 2b"))
        #expect(await compose(fix, "channa + tum hi ho") == .alreadyInSet(medley.itemId))
        #expect(entries(fix).count == 2)
        // The typed text is never rewritten.
        #expect(composer.text == "channa + tum hi ho")
    }

    @Test
    func `the row shows the key path, the time and the spelled-out medley`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        let library = fix.session.library
        let setlist = try #require(fix.session.setlists.setlist(fix.friday))
        composer.setText("kesariya in A + harbour + chan", library: library)
        let state = ComposerRowState(composer: composer, setlist: setlist, library: library)
        #expect(state.isMedley)
        #expect(state.key == "A → G → D")
        #expect(state.ghost?.text == "na Mereya")
        #expect(state.status == .medley([
            .init(title: "Kesariya", detail: "A"),
            .init(title: "Harbour Lights", detail: "G, reprise of 1"),
            .init(title: "Channa Mereya", detail: "D"),
        ]))
        #expect(state.time != "-")
        #expect(state.spokenValue.hasPrefix("Suggestion: medley of 3 songs, Kesariya"))
    }

    /// R187 composer A: ↑ / ↓ and Tab cycle the part under the caret, the ghost, list and
    /// status line follow it, and Return adds every part at its own choice; the typed text
    /// is never rewritten.
    @Test
    func `the arrows and Tab cycle the middle part under the caret`() async throws {
        let fix = try await Self.open()
        let composer = fix.session.setlists.composer
        let library = fix.session.library
        let setlist = try #require(fix.session.setlists.setlist(fix.friday))
        let typed = "kesariya in A + tum + chan"
        composer.setText(typed, library: library)
        // The caret at the end: the last part, as before.
        #expect(composer.activePart == 2)
        // Into "tum" (offset 17, between "t" and "um").
        composer.setCaret(17)
        #expect(composer.activePart == 1)
        let middle = composer.resolution.matches.map(\.id)
        #expect(Set(middle.prefix(2)) == [Self.id(1), Self.id(4)])
        var state = ComposerRowState(composer: composer, setlist: setlist, library: library)
        #expect(state.activePart == 1)
        #expect(state.matchCount == middle.count)
        let first = try SongSummary.title(#require(library.song(id: middle[0])))
        #expect(state.ghost?.text == "   → \(first)")

        #expect(composer.cycle(by: 1))
        #expect(composer.partChoices == [0, 1, 0])
        #expect(composer.showsAlternatives)
        state = ComposerRowState(composer: composer, setlist: setlist, library: library)
        let second = try SongSummary.title(#require(library.song(id: middle[1])))
        #expect(state.ghost?.text == "   → \(second)")
        guard case let .medley(parts) = state.status else {
            Issue.record("expected the medley line, got \(String(describing: state.status))")
            return
        }
        #expect(parts.map(\.title) == ["Kesariya", second, "Channa Mereya"])
        // The key path follows the cycled middle song.
        let secondKey = middle[1] == Self.id(4) ? "E" : "A"
        #expect(state.key == "A → \(secondKey) → D")

        // Back to the end: the last part's own alternatives, the middle's pick kept, and
        // typing on in the last part keeps it too.
        composer.setCaret((typed as NSString).length)
        #expect(composer.activePart == 2)
        #expect(!composer.showsAlternatives)
        #expect(composer.choice == 0)
        composer.setText(typed + "na", library: library)
        #expect(composer.partChoices == [0, 1, 0])
        #expect(composer.text == typed + "na")

        // Return adds the medley with the middle part's cycled song (the same text again
        // keeps every part's choice).
        let outcome = await compose(fix, typed + "na")
        guard case .added = outcome else {
            Issue.record("expected an add, got \(outcome)")
            return
        }
        let medley = try #require(entries(fix).last?.medley)
        #expect(medley.songIds == [Self.id(0), middle[1], Self.id(2)])
        // Editing the middle part starts it again from its best match.
        composer.setText("kesariya in A + tum hi + channa", library: library)
        #expect(composer.partChoices == [0, 0, 0])
    }

    @Test
    func `a plain line for a song that is only a member adds its reprise`() async throws {
        let fix = try await Self.open()
        await compose(fix, "kesariya + tum hi ho")
        let composer = fix.session.setlists.composer
        let setlist = try #require(fix.session.setlists.setlist(fix.friday))
        composer.setText("kesariya", library: fix.session.library)
        let state = ComposerRowState(
            composer: composer,
            setlist: setlist,
            library: fix.session.library,
        )
        #expect(state.status == .note("Kesariya · also 2a in Medley: adds a reprise"))
        guard case .added = await compose(fix, "kesariya") else {
            Issue.record("expected the reprise to be added")
            return
        }
        #expect(entries(fix).last?.songId == Self.id(0))
        #expect(fix.manager.undoActionName == "Add Song")
    }

    /// The set list with a medley and a reprise above the composer typing a medley, as R187
    /// composer A draws it (ghost, key path, spelled-out status line).
    @Test
    func `the composer renders typing a medley`() async throws {
        let fix = try await Self.open()
        await compose(fix, "kesariya + tum hi ho")
        await compose(fix, "kesariya")
        let setlists = fix.session.setlists
        let setlist = try #require(setlists.setlist(fix.friday))
        setlists.composer.setText("channa in E + harb", library: fix.session.library)
        for dark in [false, true] {
            let view = SetEntriesList(
                setlist: setlist,
                model: setlists,
                library: fix.session.library,
            )
            .frame(width: 1000, height: 420)
            .background(Theme.color.ground)
            try Self.render(
                view,
                size: CGSize(width: 1000, height: 420),
                dark: dark,
                name: "composer-\(dark ? "dark" : "light")",
            )
        }
    }

    static func render(_ view: some View, size: CGSize, dark: Bool, name: String) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        try DiagramSnapshotTests.writePNG(
            image,
            to: DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "p9-3/\(name).png"),
        )
    }
}
